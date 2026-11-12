@echo off
chcp 65001 >nul
cd /d "%~dp0"
if not exist .venv ( py -3 -m venv .venv )
call .venv\Scripts\activate.bat
pip install -r requirements.txt pyinstaller
pyinstaller --noconfirm --windowed --name FRezzPadMapper --collect-all vgamepad main.py
xcopy /E /I /Y profiles dist\FRezzPadMapper\profiles
echo.
echo Executable : dist\FRezzPadMapper\FRezzPadMapper.exe
pause
