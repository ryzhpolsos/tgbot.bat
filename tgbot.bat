@rem Telegram bot in pure BATCH
@rem Yeah, it's real :3

@echo off
setlocal

rem 65001 - utf-8, %~dp0 - script location (for token.txt)
pushd "%~dp0"
chcp 65001> nul

rem set to 1 for verbose logging
set _DEBUG=0

rem read token from token.txt
for /f "tokens=*" %%i in (token.txt) do set "TOKEN=%%i"
set "ENDPOINT=https://api.telegram.org/bot%TOKEN%"

set offset=0
:main_loop
    rem mess from parse_json can break something, so setlocal
    setlocal

    if %_DEBUG%==1 ( echo.Getting updates... %offset% )
    call :api getUpdates "offset=%offset%" updates
    if %_DEBUG%==1 ( echo.Got updates )

    rem ignore errors :p
    if not "%updates.ok%"=="true" goto :main_loop

    rem for /l is stupid
    set /a updates.result.$length-=1

    rem iterate through updates
    for /l %%i in (0,1,%updates.result.$length%) do (
        rem offset+1 to prevent getting already handled updates
        set /a "offset=updates.result.%%i.update_id+1"

        rem yeah, double call (first one expands %%, second calls process_message)
        call call :process_message "%%updates.result.%%i.message.chat.id%%" "%%updates.result.%%i.message.from.first_name%%" "%%updates.result.%%i.message.text%%"
    )

    rem %offset% will expand before executing, so it can be used to set variable in parent scope
    endlocal & set "offset=%offset%"
goto :main_loop

popd
endlocal
goto :eof

rem put your bot logic inside of this subroutine
:process_message [chat_id] [first_name] [text]
    if %_DEBUG%==1 ( echo.process_message called with %~1 %~2 %~3 )

    if "%~3"=="/start" (
        call :api sendMessage "chat_id=%~1&text=Hello,+%~2!+Batch+or+PowerShell?"
        goto :eof
    )

    if /i "%~3" equ "batch" (
        call :api sendMessage "chat_id=%~1&text=BATNIKI+SILA!!!"
        goto :eof
    )

    if /i "%~3" equ "powershell" (
        call :api sendMessage "chat_id=%~1&text=Nope+:p"
        goto :eof
    )
goto :eof

rem invoke api method and parse result if needed
:api [method] [params] [output]
    if "%~3"=="" (
        curl -s "%ENDPOINT%/%~1?%~2&_=%RANDOM%" > nul 2> nul
        goto :eof
    )

    setlocal
    set "_text="
    for /f "tokens=*" %%i in ('curl -s "%ENDPOINT%/%~1?%~2&_=%RANDOM%"') do call set "_text=%%_text%%%%i"
    endlocal & call :parse_json %~3 %_text%
goto :eof

rem HELL STARTS HERE
rem just a little json parser :)
:parse_json [output] [json]
    setlocal

    set _container_mode=0
    rem _container_mode
    rem 1 -> object
    rem 2 -> array
    
    set _property_mode=0
    rem _property_mode
    rem 1  -> name
    rem 2  -> string_value
    rem 3  -> number_value
    rem 4  -> literal_value
    rem 5  -> complex_value (complex - object/array)
    rem 6  -> pending_name
    rem 7  -> pending_key_value_separator
    rem 8  -> pending_value
    rem 9  -> pending_property_separator
    rem -1 -> bypass

    set "_raw_input=%*"
    set "_output="
    set _cnt=0

    rem process raw input (%*), because cmd.exe can't handle nested quotes when using %1 - %9
    :_json_parser_arg_loop
    call set "_ch=%%_raw_input:~%_cnt%,1%%"
    if not "%_ch%"==" " (
        set "_output=%_output%%_ch%"
        set /a _cnt+=1
        goto :_json_parser_arg_loop
    )

    rem randomized replacers for " and $
    set /a _r=%RANDOM%+10000
    set _quote=#Q%_r%#
    set _quote_len=
    set _dollar=#D%_r%#

    rem get json part from input
    set /a _cnt+=1
    call set "_json_str=%%_raw_input:~%_cnt%%%"
    call set "_json_str=%%_json_str:$=%_dollar%%%"
    set "_json_str=%_json_str:"=$%"

    set "_buffer="
    set "_name="
    set _i=0

    set "_err="

    set "_complex_value_open_char="
    set "_complex_value_close_char="
    set _complex_value_count=0
    set _set_value_m=0
    
    set "_setg_data="

    rem let's go!
    :_json_parser_loop
        rem current char
        call set "_char=%%_json_str:~%_i%,1%%"

        rem empty content means end of data
        if "%_char%"=="" goto :_json_parser_loop_break

        rem process char after \
        if %_property_mode%==-1 (
            if "%_char%"=="$" (
                set "_buffer=%_buffer%%_quote%"
            )
            
            set _property_mode=%_p_property_mode%
            goto :_json_parser_loop_continue
        )

        rem set bypass mode
        if "%_char%"=="\" (
            set _property_mode=-1
            set _p_property_mode=%_property_mode%
            goto :_json_parser_loop_continue
        )

        rem start object
        if "%_char%"=="{" (
            if %_container_mode%==0 (
                set _container_mode=1
                set _property_mode=6
                set _property_mode_next=6
                set _need_length=0
                goto :_json_parser_loop_continue
            )
        )

        rem start array
        if "%_char%"=="[" (
            if %_container_mode%==0 (
                set _container_mode=2
                set _property_mode=8
                set _property_mode_next=8
                set _name=0
                set _need_length=1
                goto :_json_parser_loop_continue
            )
        )

        rem strings ($ is ")
        if "%_char%"=="$" (
            if %_property_mode%==1 (
                rem end name
                set _property_mode=7
                set "_name=%_buffer%"
                set "_buffer="
            ) else if %_property_mode%==2 (
                rem end of string value
                set _property_mode=9
            ) else if %_property_mode%==6 (
                rem start name
                set _property_mode=1
            ) else if %_property_mode%==8 (
                rem start string value
                set _property_mode=2
            ) else if %_property_mode%==5 (
                rem don't touch complex data
                set "_buffer=%_buffer%%_quote%"
            ) else (
                set "_err=Invalid syntax: unexpected quote at %_i%"
                goto :_throw
            )

            goto :_json_parser_loop_continue
        )

        rem complex value (array/object)
        if %_property_mode%==5 (
            set "_buffer=%_buffer%%_char%"

            if "%_char%"=="%_complex_value_open_char%" (
                set /a _complex_value_count+=1
            ) else if "%_char%"=="%_complex_value_close_char%" (
                rem check if end is reached
                set /a _complex_value_count-=1
                call :_check_cp_set_value
                goto :_json_parser_loop_continue
            )
        )
        
        rem number value
        if %_property_mode%==3 (
            for %%i in (0 1 2 3 4 5 6 7 8 9) do (
                if "%_char%"=="%%i" ( set "_buffer=%_buffer%%%i" & goto :_json_parser_loop_continue )
            )
            
            call :_check_set_value
        )

        rem literal value (true/false/null)
        if %_property_mode%==4 (
            if "%_char%"=="}" (
                call :_check_bn_set_value
            ) else if "%_char%"=="," (
                call :_check_bn_set_value
            ) else if "%_char%"=="]" (
                call :_check_bn_set_value
            ) else (
                set "_buffer=%_buffer%%_char%"
            )
        )

        rem set "pending value" mode if encoutered ":"
        if %_property_mode%==7 (
            if "%_char%"==":" ( set _property_mode=8 )
        )

        rem start value
        if %_property_mode%==8 (
            rem start number value
            for %%i in (0 1 2 3 4 5 6 7 8 9) do (
                if "%_char%"=="%%i" (
                    set _property_mode=3
                    set "_buffer=%_char%"
                    goto :_json_parser_loop_continue
                )
            )

            rem start literal value
            for %%i in (a b c d e f g h i j k l m n i o p q r s t u v w x y z) do (
                if "%_char%"=="%%i" (
                    set _property_mode=4
                    set "_buffer=%_char%"
                    goto :_json_parser_loop_continue
                )
            )

            rem start object
            if "%_char%"=="{" (
                set _property_mode=5
                set "_buffer=%_char%"
                set _complex_value_count=1
                set "_complex_value_open_char={"
                set "_complex_value_close_char=}"
                goto :_json_parser_loop_continue
            )

            rem start array
            if "%_char%"=="[" (
                set _property_mode=5
                set "_buffer=%_char%"
                set _complex_value_count=1
                set "_complex_value_open_char=["
                set "_complex_value_close_char=]"
                goto :_json_parser_loop_continue
            )
        )

        if %_property_mode%==9 (
            call :_set_value
        )
        
        if %_set_value_m%==0 (
            rem add char to buffer if needed
            for %%i in (1 2) do (
                if %_property_mode%==%%i ( set "_buffer=%_buffer%%_char%" & goto :_json_parser_loop_continue )
            )
        ) else (
            set /a _set_value_m-=1
        )
    :_json_parser_loop_continue

    if %_DEBUG%==1 ( echo.[%_i%] %_property_mode% %_container_mode% '%_char%' '%_name%' '%_buffer%' )
    set /a _i+=1
    goto :_json_parser_loop
    :_json_parser_loop_break

    rem add $length property to array
    if "%_need_length%"=="1" (
        call :_add_global_var "%_output%.$length" %_name%
    )

    rem syntax error handler
    :_throw
    if not "%_err%"=="" (
        set "%_output%=ERR: %_err%"
        echo.[JSON] %_err%
        goto :eof
    )

    rem throw variables to global scope
    endlocal & call :_setg %_setg_data%
goto :eof

rem check complex value
:_check_cp_set_value
    if not %_complex_value_count%==0 ( goto :eof )

    rem reached end, can set value
    call :_prepare_buffer

    rem call parse_json for sub-element
    call :parse_json %_output%.%_name% %_buffer%
    set _property_mode=9
    set "_buffer="

    rem register variables for _setg
    for /f "tokens=1,* delims==" %%i in ('set %_output%.%_name% 2^>nul') do call :_add_global_var "%%~i" "%%~j"
goto :eof

rem check literal value
:_check_bn_set_value
    if "%_buffer%"=="true" (
        call :_set_value
    ) else if "%_buffer%"=="false" (
        call :_set_value
    ) else if "%_buffer%"=="null" (
        call :_set_value
    ) else (
        set "_err=Invalid syntax: unexpected literal %_buffer%"
        goto :_throw
    )
goto :eof

rem check if end of property value reached
:_check_set_value
    if "%_char%"=="}" (
        call :_set_value
    ) else if "%_char%"=="]" (
        call :_set_value
    ) else if "%_char%"=="," (
        call :_set_value
    )
goto :eof

rem set property value
:_set_value
    if %_set_value_m%==0 (
        call :_prepare_buffer
        call :_add_global_var "%_output%.%_name%" "%_buffer%"
        set "_buffer="
        
        call :_move_next

        rem reset container mode on container end
        if "%_char%"=="}" (
            set _container_mode=0
        ) else if "%_char%"=="]" (
            set _container_mode=0
        )
    ) else (
        set /a _set_value_m-=1
    )
goto :eof

rem replace back #Q[random mess] to ", #D[random mess] to $
:_prepare_buffer
    call set "_buffer=%%_buffer:%_quote%="%%"
    call set "_buffer=%%_buffer:%_dollar%=$%%"
goto :eof

rem register variable for _setg
:_add_global_var
    if %_DEBUG%==1 ( echo Adding global var: %~1=%~2 )
    set "_setg_data=%_setg_data%"%~1" "%~2" "
goto :eof

rem set variables listed in arguments
:_setg
    :_setg_loop
        set "%~1=%~2" 2>nul
        shift /1
        shift /1
    if not "%~1"=="" goto :_setg_loop
goto :eof

rem increase array index
:_move_next
    set _property_mode=%_property_mode_next%
    
    if %_container_mode%==2 (
        set /a _name+=1
    )
goto :eof