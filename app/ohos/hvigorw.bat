@echo off
rem Run DevEco Studio bundled hvigor 6.22.3 directly, with NODE_PATH junctions
rem exposing the SAME physical packages so plugins and CLI share one instance.
rem Purge project-local @ohos copies (IDE sync / npm may drop 5.2.2 here);
rem they would shadow the NODE_PATH junctions and split the hvigor singleton.
if exist "%~dp0node_modules\@ohos" rmdir /s /q "%~dp0node_modules\@ohos"
set "NODE_PATH=D:\hvigor-node"
set "DEVECO_SDK_HOME=D:\soft\DevEco Studio\sdk"
set "PATH=D:\soft\DevEco Studio\tools\ohpm\bin;%PATH%"
node "D:\soft\DevEco Studio\tools\hvigor\hvigor\bin\hvigor.js" %*
