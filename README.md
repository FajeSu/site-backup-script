## Site backup script
Скрипт для архивации базы данных и файлов сайта с последующей отправкой на Яндекс.Диск. Основан на аналогичном [скрипте от Сергея Луконина](http://neblog.info/skript-bekapa-na-yandeks-disk/).

### Технические требования
* Unix-подобная операционная система
* coreutils 8.16+
* pv 1.1.4+ ([Pipe Viewer](https://github.com/icetee/pv))
* grep 2.5.4+
* tar 1.14+
* gzip 1.3.12+
* bc 1.03+

### Установка и настройка
1. [Зарегистрировать приложение](https://yandex.ru/dev/oauth/doc/dg/tasks/register-client-docpage/) в Яндекс.OAuth для аккаунта, Яндекс.Диск которого будет использоваться для хранения бэкапов

    1.1. **Платформы**. Выбрать "_Веб-сервисы_", ниже нажать на ссылку "_Подставить URL для разработки_"

    1.2. **Доступы**. В группе "_Яндекс.Диск REST API_" поставить 2 галочки:
      * Доступ к информации о Диске
      * Доступ к папке приложения на Диске

2. [Получить токен](https://yandex.ru/dev/oauth/doc/dg/tasks/get-oauth-token-docpage/) вручную

3. Загрузить скрипт на свой сервер и в настройках использовать полученный токен:
```
git clone https://github.com/FajeSu/site-backup-script.git ~/site-backup-script/
cd ~/site-backup-script/
cp _settings.sh.source _settings.sh
vim _settings.sh
```

### Использование
* **Обязательные ключи командной строки:**
<table>
<tr>
<td align="left" valign="top" width="165px"><code>-project-name</code></td>
<td align="left" valign="top">Название проекта, используется в журналах событий и именах архивов</td>
</tr>
<tr>
<td align="left" valign="top"><code>-db-user</code></td>
<td>Пользователь базы данных (<strong>для режима db</strong>)</td>
</tr>
<tr>
<td align="left" valign="top"><code>-db-pass</code></td>
<td align="left" valign="top">Пароль пользователя базы данных (<strong>для режима db</strong>)</td>
</tr>
<tr>
<td align="left" valign="top"><code>-project-dirs</code></td>
<td align="left" valign="top">Директории для архивации, через запятую (<strong>для режима files</strong>)</td>
</tr>
</table>

* **Необязательные ключи командной строки:**
<table>
<tr>
<td align="left" valign="top" width="165px"><code>-mode</code></td>
<td align="left" valign="top">Выбор объекта архивации (<strong>режим</strong>):<br />
<ul>
<li><strong>db</strong> (база данных)</li>
<li><strong>files</strong> (локальные файлы)</li>
</ul>
По-умолчанию "<i>db,files</i>", т.е. и БД, и файлы. Если указан только один объект, то обязательные ключи для другого становятся необязательными
</td>
</tr>
<tr>
<td align="left" valign="top"><code>-db-host</code></td>
<td align="left" valign="top">Сервер базы данных (по-умолчанию - <i>localhost</i>)</td>
</tr>
<tr>
<td align="left" valign="top"><code>-db-name</code></td>
<td align="left" valign="top">Название базы данных (по-умолчанию используются данные из ключа <code>-db-user</code>)</td>
</tr>
<tr>
<td align="left" valign="top"><code>-max-backups</code></td>
<td align="left" valign="top">Максимальное количество бэкапов, хранимых на Яндекс.Диске (0 - хранить все бэкапы, по-умолчанию - 12)</td>
</tr>
<tr>
<td align="left" valign="top"><code>-no-remove-local</code></td>
<td align="left" valign="top">Не удалять локальные архивы</td>
</tr>
<tr>
<td align="left" valign="top"><code>-no-upload</code></td>
<td align="left" valign="top">Не загружать бэкап на Яндекс.Диск (при этом включается ключ <code>-no-remove-local</code>)</td>
</tr>
</table>

### Примеры
```
# Архивирование БД и файлов сайта. Максимальное кол-во хранимых бэкапов - 8
/bin/bash ~/site-backup-script/backup_script.sh -project-name site-domain.com -db-user username -db-pass password -project-dirs ~/site-domain.com/public_html/ -max-backups 8

# Архивирование только БД
/bin/bash ~/site-backup-script/backup_script.sh -project-name site-domain.com -mode db -db-user username -db-pass password

# Архивирование только файлов
/bin/bash ~/site-backup-script/backup_script.sh -project-name site-domain.com -mode files -project-dirs ~/site-domain.com/public_html/

# Архивирование отдельных файлов или директорий
/bin/bash ~/site-backup-script/backup_script.sh -project-name site-domain.com -mode files -project-dirs ~/site-domain.com/public_html/index.html,~/site-domain.com/public_html/tmp/

# Архивирование БД с другого сервера. На стороне того сервера необходимо дать доступ на подключение с определенного IP
/bin/bash ~/site-backup-script/backup_script.sh -project-name another-site.org -mode db -db-host another-site.org -db-name another_db -db-user another_user -db-pass another_password
```

### Структура каталогов на Яндекс.Диске
```
Корневой каталог
└ Приложения
  └ <app-name>
    └ <project-name>
      └ <backup-time>
        └ файлы архивов
```
где
<table>
<tr>
<td align="left" valign="top" width="165px"><code>&lt;app-name&gt;</code></td>
<td align="left" valign="top">Название приложения, указанное не этапе его регистрации</td>
</tr>
<tr>
<td align="left" valign="top"><code>&lt;project-name&gt;</code></td>
<td>Название проекта</td>
</tr>
<tr>
<td align="left" valign="top"><code>&lt;backup-time&gt;</code></td>
<td>Дата и время запуска скрипта на сервере, вида 20191231-235959</td>
</tr>
</table>
