@echo off
rem Start the FastAPI backend if it is not already running. Safe to call repeatedly.
rem   start_backend.bat        -> if port 8000 is free, open a minimized window running the server
rem   start_backend.bat run    -> run the server in THIS window (used internally)
rem Used as a "Before launch" step of the Flutter run configuration (CLAUDE.md section 13).
rem ASCII only on purpose: cmd reads .bat files in the console code page (cp949).

setlocal
set "ROOT=%~dp0.."
set "PY=C:\Users\USER\anaconda3\envs\philo-rag\python.exe"

if /i "%~1"=="run" goto run

netstat -ano | findstr /r /c:":8000 .*LISTENING" >nul
if not errorlevel 1 (
    echo backend already running on port 8000
    exit /b 0
)

if not exist "%PY%" (
    echo ERROR: %PY% not found. Create the conda env philo-rag first.
    exit /b 1
)

echo starting backend in a minimized window...
start "philo-rag backend" /min cmd /k call "%~f0" run
exit /b 0

:run
rem A program started before HF_HOME was set (an IDE left open) does not inherit it, and the
rem model (2.2GB) would be downloaded again into C:\Users\...\.cache. Read it from the registry.
rem On a PC where HF_HOME is not set this does nothing and the default cache is used.
if not defined HF_HOME for /f "tokens=2,*" %%A in ('reg query "HKCU\Environment" /v HF_HOME 2^>nul ^| findstr /i "HF_HOME"') do set "HF_HOME=%%B"
if defined HF_HOME echo HF_HOME=%HF_HOME%
rem The model is already cached; skip the online check so startup does not wait on the network.
if defined HF_HOME if exist "%HF_HOME%\hub\models--BAAI--bge-m3" set "HF_HUB_OFFLINE=1"
cd /d "%ROOT%\backend"
set "PYTHONUTF8=1"
"%PY%" -m uvicorn app.main:app --host 0.0.0.0 --port 8000
