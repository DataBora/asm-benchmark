@echo off
set path=%path%;c:\masm32\bin
set include=c:\masm32\include
set lib=c:\masm32\lib

ml /c /Zd /coff readcsv2.asm
if errorlevel 1 goto error

link /subsystem:console readcsv2.obj
if errorlevel 1 goto error

readcsv2.exe
goto end

:error
echo Compilation or linking failed
pause

:end