@ECHO off
REM The fake devin (devin.mjs) on Windows, a .cmd beside it as grok.cmd is: the station runs the script with Node.
SET dp0=%~dp0
SET "_prog=node"
"%_prog%"  "%dp0%\devin.mjs" %*
