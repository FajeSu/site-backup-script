## Site backup script
Скрипт для архивации базы данных и файлов сайта с последующей отправкой на Яндекс.Диск. Основан на аналогичном [скрипте от Сергея Луконина](http://neblog.info/skript-bekapa-na-yandeks-disk/).

### Установка и настройка
1) Зарегистрировать приложение и получить токен в [Яндекс.OAuth](https://tech.yandex.ru/oauth/doc/dg/concepts/about-docpage)

2) Загрузить скрипт на хостинг и в настройках использовать полученный токен:
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
<td align="left" valign="top" width="150px"><code>-project-name</code></td>
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
<td align="left" valign="top" width="150px"><code>-mode</code></td>
<td align="left" valign="top">Выбор объекта архивации (<strong>режим</strong>):<br />
<ul>
<li><strong>db</strong> (база данных)</li>
<li><strong>files</strong> (локальные файлы)</li>
</ul>
По-умолчанию "db,files", т.е. и БД, и файлы. Если указан только один объект, то обязательные ключи для другого становятся необязательными
</td>
</tr>
<tr>
<td align="left" valign="top"><code>-db-host</code></td>
<td align="left" valign="top">Сервер базы данных (по-умолчанию - localhost)</td>
</tr>
<tr>
<td align="left" valign="top"><code>-db-name</code></td>
<td align="left" valign="top">Название базы данных (по-умолчанию используются данные из ключа <code>-db-user</code>)</td>
</tr>
<tr>
<td align="left" valign="top"><code>-max-backups</code></td>
<td align="left" valign="top">Максимальное количество бэкапов, хранимых на Яндекс.Диске (0 - хранить все бэкапы, по-умолчанию - 12)</td>
</tr>
</table>

### Примеры
```
# Архивирование БД и файлов сайта. Максимальное кол-во хранимых бэкапов = 8.
/bin/bash ~/site-backup-script/backup_script.sh -project-name site-domain.com -db-user username -db-pass password -project-dirs ~/site-domain.com/public_html/ -max-backups 8

# Архивирование только БД
/bin/bash ~/site-backup-script/backup_script.sh -project-name site-domain.com -mode db -db-user username -db-pass password

# Архивирование только файлов
/bin/bash ~/site-backup-script/backup_script.sh -project-name site-domain.com -mode files -project-dirs ~/site-domain.com/public_html/

# Архивирование отдельных файлов или директорий
/bin/bash ~/site-backup-script/backup_script.sh -project-name site-domain.com -mode files -project-dirs ~/site-domain.com/public_html/.htaccess,~/site-domain.com/public_html/robots.txt,~/site-domain.com/public_html/tmp/

# Архивирование БД с другого сервера. Для этого на стороне сервера необходимо дать доступ на подключение с определенного IP.
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
<table>
<tr>
<td align="left" valign="top" width="60px" rowspan="3">где</td>
<td align="left" valign="top"><code>&lt;app-name&gt;</code> - название приложения, указанное не этапе регистрации;</td>
</tr>
<tr>
<td><code>&lt;project-name&gt;</code> - название проекта;</td>
</tr>
<tr>
<td><code>&lt;backup-time&gt;</code> - дата и время запуска скрипта на сервере, вида 20191231-235959</td>
</tr>
</table>
