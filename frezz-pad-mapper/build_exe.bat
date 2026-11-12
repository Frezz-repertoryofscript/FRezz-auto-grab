@echo off
chcp 65001 >nul
cd /d "%~dp0"
if not exist .venv ( py -3 -m venv .venv )
call .venv\Scripts\activate.bat
set VGAMEPAD_SKIP_VIGEMBUS_INSTALL=true
pip install -r requirements.txt pyinstaller
pyinstaller --noconfirm --onefile --windowed --name FRezzPadMapper --collect-data vgamepad --collect-binaries vgamepad --hidden-import vgamepad.win.virtual_gamepad --hidden-import vgamepad.win.vigem_client --add-data "profiles;profiles" main.py
echo.
echo Executable : dist\FRezzPadMapper\FRezzPadMapper.exe
pause
