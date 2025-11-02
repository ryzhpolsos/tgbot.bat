# tgbot.bat
Telegram-бот на чистом Batch с полноценным рекурсивным (но медленным) парсером JSON

## ЗАЧЕМ???
А почему бы и нет?

## КАК???
Скачать файл, положить рядышком с ним `token.txt`, куда засунуть токен от бота.


## ХОЧУ СВОЕГО БОТА!!!
Логика обработки сообщений находится в подпрограмме `process_message`:
```batch
rem put your bot logic inside of this subroutine
:process_message [chat_id] [first_name] [text]
    if %_DEBUG%==1 ( echo.process_message called with %~1 %~2 %~3 )

    rem Самое место, чтобы обработать какое-нибудь сообщение!
goto :eof
```
- ID чата, куда было отправлено сообщение: `%~1`
- Отображаемое имя отправителя: `%~2`
- Текст сообщения: `%~3`
- Отправка сообщения: `call :api sendMessage "chat_id=%~1&text=Hello,+%~2!"` (пробелы в тексте необходимо заменять на `+`)

Если нужна более сложная логика, добавьте больше аргументов в вызов `process_message` (см. строку с текстом `call call :process_message`)

Пример бота-калькулятора (осторожно, он уязвим к инъекциям команд!)
```batch
rem put your bot logic inside of this subroutine
:process_message [chat_id] [first_name] [text]
    if %_DEBUG%==0 ( echo.process_message called with %~1 %~2 %~3 )

    if "%~3"=="/start" (
        call :api sendMessage "chat_id=%~1&text=Hello,+%~2!"
        goto :eof
    )

    set /a "result=%~3"
    call :api sendMessage "chat_id=%~1&text=%result%"
goto :eof
```

## А МОЖНО???
Можно, лицензия - [MIT](https://github.com/ryzhpolsos/tgbot.bat/blob/main/LICENSE)
