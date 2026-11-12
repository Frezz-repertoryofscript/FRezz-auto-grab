@echo off
chcp 65001 >nul
cd /d "%~dp0"
if not exist .venv ( py -3 -m venv .venv )
call .venv\Scripts\activate.bat
pip install -r requirements.txt pyinstaller
pyinstaller --noconfirm --onefile --windowed --name FRezzPadMapper --collect-all vgamepad --add-data "profiles;profiles" main.py
echo.
echo Executable : dist\FRezzPadMapper\FRezzPadMapper.exe
pause
