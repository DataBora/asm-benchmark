@echo off
set path=%path%;c:\masm32\bin
set include=c:\masm32\include
set lib=c:\masm32\lib

ml /c /Zd /coff readjson.asm
if errorlevel 1 goto error

link /subsystem:console readjson.obj
if errorlevel 1 goto error

readjson.exe
goto end

:error
echo Compilation or linking failed
pause

:end