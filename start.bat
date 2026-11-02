@echo off
rem Run from the folder this file is in, even when double-clicked from elsewhere
cd /d "%~dp0"

where bundle >nul 2>nul
if errorlevel 1 (
  echo Bundler not found. Install Ruby from https://rubyinstaller.org/ then run: gem install bundler
  pause
  exit /b 1
)

rem Install missing gems automatically (does nothing if they are already installed)
call bundle check >nul 2>nul || call bundle install
if errorlevel 1 (
  echo Failed to install gems. See the error above.
  pause
  exit /b 1
)

rem Run with the exact gem versions from Gemfile.lock
call bundle exec ruby cakee.rb
pause
