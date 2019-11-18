#!/bin/bash
#
# Скрипт для архивации базы данных и файлов сайта
# с последующей отправкой на Яндекс.Диск
#
# Основан на аналогичном скрипте от Сергея Луконина
# http://neblog.info/skript-bekapa-na-yandeks-disk/
#
# Версия: 1.2.2
# Автор: Евгений Хованский <fajesu@ya.ru>
# Copyright: (с) 2019 Digital Fresh
# Сайт: https://www.d-fresh.ru/
#
# Обязательные ключи командной строки:
# -project-name название проекта, используется в журналах событий
#               в именах архивов
# -db-user      пользователь базы данных (для режима db)
# -db-pass      пароль пользователя базы данных (для режима db)
# -project-dirs директории для архивации, через запятую (для режима files)
#
# Необязательные ключи командной строки:
# -mode         выбор объекта архивации (режим):
#                 - db (база данных)
#                 - files (локальные файлы)
#               (по-умолчанию "db,files", т.е. и БД, и файлы)
#               (если указан только один объект, то обязательные
#               ключи для другого становятся необязательными)
# -db-host      сервер базы данных
#               (по-умолчанию - localhost)
# -db-name      название базы данных
#               (по-умолчанию используются данные из
#               ключа -db-user)
# -max-backups  максимальное количество бэкапов,
#               хранимых на Яндекс.Диске
#               (0 - хранить все бэкапы)
#               (по-умолчанию - 12)
# ------------------------------------------------------------


# --- Константы ---

# Путь до скрипта
# Используется в путях до архивов и файлов журналов событий
declare -r script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Время запуска скрипта
# Используется в именах архивов
declare -r backup_time="$(date "+%Y%m%d-%H%M%S")"

# Имя временного файла журнала событий
declare -r log_tmp_file="$(basename -s .sh "${BASH_SOURCE[0]}")_tmp_log_${backup_time}_$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8).txt"

# Массив ответов сервера при загрузке файла на Яндекс.Диск
declare -r -A upload_response_code_statuses=(
  ["413"]="Размер файла превышает 10 ГБ"
  ["500"]="Внутренняя ошибка сервера"
  ["503"]="Сервер временно недоступен"
  ["507"]="Недостаточно места"
)


# --- Стандартные значения переменных настроек ---
# Настройки должны храниться в файле "_settings.sh" рядом с файлом скрипта
ya_token=""
log_file=""
send_log_to=""
send_log_from=""
send_log_errors_only=true

# Загружаем настройки
. "$script_path/_settings.sh"

# ------

# Добавление даты в начало строки события
function getLoggerString() {
  echo "[$(date "+%Y-%m-%d %H:%M:%S")] $1"
}

# Запись события во временный файл журнала
function logger() {
  echo -e "$(getLoggerString "$1")" >> "$script_path/$log_tmp_file"

  if [ -n "$send_log_to" ] && [ "$2" = "error" ]; then
    email_log_error=true
  fi
}

# Подготовка переменных
# Обработка ключей командной строки
function prepareVars() {
  if [ -z "$send_log_from" ]; then
    send_log_from="$send_log_to"
  fi

  if [ -z "$send_log_errors_only" ]; then
    send_log_errors_only=false
  fi

  if [ -z "$ya_token" ]; then
    logger "Ошибка! Не задано значение переменной \"ya_token\" в настройках" "error"

    return 1
  fi

  while [ -n "$1" ]; do
    case "$1" in
      -project-name)
        project_name="$2"
      ;;
      -mode)
        mode="$2"
      ;;

      -db-user)
        mysql_user="$2"
      ;;
      -db-pass)
        mysql_pass="$2"
      ;;
      -project-dirs)
        backup_dirs="${2//\~/$HOME}"
        backup_dirs="${backup_dirs//,/ }"
      ;;

      -db-host)
        mysql_server="$2"
      ;;
      -db-name)
        mysql_db="$2"
      ;;
      -max-backups)
        max_backups="$2"
      ;;
    esac

    shift # past argument
    shift # past value
  done


  local -A vars=(
    ["-project-name"]="$project_name"
  )

  local mode_tmp="$mode"
  mode=""
  if [[ $mode_tmp =~ "db" ]]; then
    mode="db"
  fi
  if [[ $mode_tmp =~ "files" ]]; then
    if [ -n "$mode" ]; then
      mode="${mode},"
    fi

    mode="${mode}files"
  fi
  if [[ -z $mode ]]; then
    mode="db,files"
  fi

  if [[ $mode =~ "db" ]]; then
    vars["-db-user"]="$mysql_user"
    vars["-db-pass"]="$mysql_pass"
  fi
  if [[ $mode =~ "files" ]]; then
    vars["-project-dirs"]="$backup_dirs"
  fi

  local key
  local error
  for key in "${!vars[@]}"; do
    if [ -z "${vars[$key]}" ]; then
      error="Ошибка! Не указан ключ командной строки: $key"

      if [ -n "$project_name" ]; then
        error="$project_name - $error"
      fi

      logger "$error" "error"
      logger "Обязательные ключи командной строки: ${!vars[*]}"

      return 1
    fi
  done

  if [ -z "$mysql_server" ]; then
    mysql_server="localhost"
  fi

  if [ -z "$mysql_db" ]; then
    mysql_db="$mysql_user"
  fi

  if [ -z "$max_backups" ]; then
    max_backups="12"
  fi

  return 0
}

# Создание архивов базы данных и файлов
function createLocalFiles() {
  mkdir "$script_path/${project_name}_${backup_time}"

  if [[ $mode =~ "db" ]]; then
    logger "Создание архива базы данных: dump_mysql_${project_name}_${backup_time}.sql.gz"
    local mysql_error="$(((mysqldump -h "$mysql_server" -u "$mysql_user" -p"$mysql_pass" "$mysql_db" | gzip -9c | pv -qL 1M | split -b 2GB -d --additional-suffix=.sql.gz - "$script_path/${project_name}_${backup_time}/dump_mysql_${project_name}_${backup_time}_") 2>&1) | grep -v "Warning: Using a password")"
    if [ -n "$mysql_error" ]; then
      logger "$mysql_error" "error"

      return 1
    fi
  fi

  if [[ $mode =~ "files" ]]; then
    logger "Создание архива каталогов: files_${project_name}_${backup_time}.tar.gz"
    local files_error="$((tar -cP $backup_dirs | gzip -9c | pv -qL 1M | split -b 2GB -d --additional-suffix=.tar.gz - "$script_path/${project_name}_${backup_time}/files_${project_name}_${backup_time}_") 2>&1)"
    if [ -n "$files_error" ]; then
      logger "$files_error" "error"

      return 1
    fi
  fi

  return 0
}

# Получение значения по ключу из данных json
# Использование: getByKeyFromJson "key" "json"
function getByKeyFromJson() {
  local regex="\"$1\":\"?([^\",\}]+)\"?"
  local output
  [[ $2 =~ $regex ]] && output="${BASH_REMATCH[1]}"
  echo "$output"
}

# Проверка наличия ошибки в ответе Яндекса
function checkError() {
  echo "$(getByKeyFromJson "error" "$1")"
}

# Получение понятного для восприятия размера файла
function getHumanReadableFileSize() {
  local file_size="$(du -b $1 2>&1)"

  if [[ $file_size =~ ^"du: " ]]; then
    logger "$file_size" "error"
    echo ""
  else
    file_size="$(echo $file_size | awk '
      function convertFileSize(bytes) {
        size_name[1024^4]="ТиБ";
        size_name[1024^3]="ГиБ";
        size_name[1024^2]="МиБ";
        size_name[1024]="КиБ";

        for (x = 1024^4; x >= 1024; x /= 1024) {
          if (bytes >= x) {
            return sprintf("%.2f %s", bytes/x, size_name[x]);
          }
        }

        return sprintf("%d Б", bytes);
      }
      {print convertFileSize($1)}
    ' 2>/dev/null)"

    echo "$file_size"
  fi
}

# Получение адреса для загрузки файла
function getUploadUrl() {
  local json_out="$(curl -s -H "Authorization: OAuth $ya_token" -H "Accept: application/json" -H "Content-Type: application/json" "https://cloud-api.yandex.net:443/v1/disk/resources/upload/?path=app:/$1&overwrite=true")"
  local json_error="$(checkError "$json_out")"
  if [ -n "$json_error" ]; then
    logger "Ошибка получения адреса для загрузки файла $1: $json_error" "error"
    echo ""
  else
    echo "$(getByKeyFromJson "href" "$json_out")"
  fi
}

# Загрузка одного файла
function uploadFile() {
  local file_basename="$(basename "$1")"
  local file_size="$(getHumanReadableFileSize "$1")"

  if [ -n "$file_size" ]; then
    file_size=" ($file_size)"
  fi

  logger "Загрузка файла ${file_basename}${file_size} на Яндекс.Диск"

  local upload_url="$(getUploadUrl "$project_name/$backup_time/$file_basename")"
  if [ -n "$upload_url" ]; then
    local response_code="$(curl -s -T "$1" -H "Authorization: OAuth $ya_token" -H "Accept: application/json" -H "Content-Type: application/json" -o /dev/null -w "%{http_code}" "$upload_url")"

    if [ -n "$response_code" ] && [ -n "${upload_response_code_statuses[$response_code]}" ]; then
      logger "Ошибка загрузки файла $file_basename: $response_code - ${upload_response_code_statuses[$response_code]}" "error"

      return 1
    fi
  fi

  return 0
}

# Удаление локального файла
function removeLocalFile() {
  logger "Удаление локального файла $(basename "$1")"
  rm -f "$1"
}

# Загрузка архивов на Яндекс.Диск
function upload() {
  local json_out
  local json_error

  # Создание директорий на Яндекс.Диске
  local path=""
  local value
  for value in "$project_name" "$backup_time"; do
    path="$path$value/"

    json_out="$(curl -X PUT -s -H "Authorization: OAuth $ya_token" -H "Accept: application/json" -H "Content-Type: application/json" "https://cloud-api.yandex.net:443/v1/disk/resources/?path=app:/$path")"
    json_error="$(checkError "$json_out")"
    if [ -n "$json_error" ] && [ "$json_error" != "DiskPathPointsToExistentDirectoryError" ]; then
      logger "Ошибка создания директории $path в каталоге приложения на Яндекс.Диске: $json_error" "error"

      return 1
    fi
  done

  # Загрузка архивов
  local file
  for file in $script_path/${project_name}_${backup_time}/*; do
    if [ -f "$file" ]; then
      uploadFile "$file"

      if [ $? -ne 0 ]; then
        return 2
      fi

      # Удаление архива после успешной загрузки
      removeLocalFile "$file"
    fi
  done

  return 0
}

# Получение списка директорий, вложенных в каталог проекта
# https://tech.yandex.ru/disk/api/reference/meta-docpage/
function yandexDirList() {
  curl -s -H "Authorization: OAuth $ya_token" -H "Accept: application/json" -H "Content-Type: application/json" "https://cloud-api.yandex.net:443/v1/disk/resources?path=app:/$project_name&fields=_embedded.items.name&limit=999&sort=-created&offset=$max_backups" | tr "{},[]" "\n" | grep "name" | cut -d: -f 2 | tr -d "\""
}

# Удаление старых бэкапов на Яндекс.Диске
function removeCloudOldBackups() {
  if [ "$max_backups" -gt 0 ]; then
    local dirs=($(yandexDirList))
    if [ "${#dirs[@]}" -gt 0 ]; then
      logger "Удаление старых бэкапов на Яндекс.Диске"

      local dir
      for dir in "${dirs[@]}"; do
        curl -X DELETE -s -H "Authorization: OAuth $ya_token" "https://cloud-api.yandex.net:443/v1/disk/resources?path=app:/$project_name/$dir&force_async=true&permanently=true" >/dev/null
      done
    fi
  fi
}

# Удаление последнего бэкапа на Яндекс.Диске после ошибки загрузки
function removeCloudLastBackup() {
  logger "Удаление последнего бэкапа на Яндекс.Диске, загруженного с ошибкой"

  curl -X DELETE -s -H "Authorization: OAuth $ya_token" "https://cloud-api.yandex.net:443/v1/disk/resources?path=app:/$project_name/$backup_time&force_async=true&permanently=true" >/dev/null
}

# Отправка письма с результатом выполнения скрипта
function mailing() {
  if [ -n "$send_log_to" ]; then
    if [ "$send_log_errors_only" = false ] || ([ ! "$send_log_errors_only" = false ] && [ "$email_log_error" = true ]); then
      if [[ "$(mail -V)" =~ "mailutils" ]]; then
        local mail_error="$(mail -s "Site backup script log" -a "From: $send_log_from" -a "Content-type: text/plain; charset=utf-8" "$send_log_to" <<<"$(cat "$script_path/$log_tmp_file")
$(getLoggerString "$1")" 2>&1)"
      else
        local mail_error="$(mail -s "Site backup script log" -r "$send_log_from" -S content-type="text/plain; charset=utf-8" "$send_log_to" <<<"$(cat "$script_path/$log_tmp_file")
$(getLoggerString "$1")" 2>&1)"
      fi

      if [ -n "$mail_error" ]; then
        logger "Ошибка отправки почты! $mail_error"

        return 1
      fi
    fi
  fi
}

# Удаление локальных архивов
function removeLocalFiles() {
  logger "Удаление локальных архивов"
  rm -fr "$script_path/${project_name}_${backup_time}"
}

# Запись событий в общий файл журнала и удаление временного
function writeLog() {
  if [ -z "$log_file" ]; then
    log_file="$(basename -s .sh "${BASH_SOURCE[0]}")_log.txt"
  fi

  cat "$script_path/$log_tmp_file" >> "$script_path/$log_file"

  rm -f "$script_path/$log_tmp_file"
}

# -----

# Название проекта
# Используется в журнале событий и в именах архивов
declare project_name

# Объект архивации: база данных, локальные файлы
declare mode

# Сервер базы данных
declare mysql_server

# Пользователь базы данных
declare mysql_user

# Пароль пользователя базы данных
declare mysql_pass

# Имя базы данных
declare mysql_db

# Директории для архивации (указываются через пробел),
# которые будут помещены в единый архив и отправлены на Яндекс.Диск
declare backup_dirs

# Максимальное количество бэкапов, хранимых на Яндекс.Диске
declare max_backups

# Результат выполнения скрипта содержит ошибки
declare email_log_error=false

# -----

logger "--- Начало выполнения скрипта ---"
shopt -s nocasematch

prepareVars $*
if [ $? -eq 0 ]; then
  logger "Проект: $project_name"

  createLocalFiles

  if [ $? -eq 0 ]; then
    upload

    case $? in
      # Ошибок нет
      # Удаляем старые бэкапы
      0)
        removeCloudOldBackups
      ;;
      # Ошибка создания директории на Яндекс.Диске
      # Ничего не делаем
      1)
      ;;
      # Ошибка загрузки файла на Яндекс.Диск
      # Удаляем последний загруженный бэкап
      2)
        removeCloudLastBackup
      ;;
    esac
  fi

  removeLocalFiles
fi
shopt -u nocasematch

mailing "--- Завершение выполнения скрипта ---"
logger "--- Завершение выполнения скрипта ---\n"
writeLog
