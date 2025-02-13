@echo off
set path=%path%;c:\masm32\bin
set include=c:\masm32\include
set lib=c:\masm32\lib

ml /c /Zd /coff readcsv.asm
if errorlevel 1 goto error

link /subsystem:console readcsv.obj
if errorlevel 1 goto error

readcsv.exe
goto end

:error
echo Compilation or linking failed
pause

:end