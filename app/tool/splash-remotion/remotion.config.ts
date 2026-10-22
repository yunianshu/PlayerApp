import { Config } from '@remotion/cli/config';

// 用本机 Chrome 渲染，免下载 headless shell。
Config.setBrowserExecutable('C:/Program Files/Google/Chrome/Application/chrome.exe');
Config.setVideoImageFormat('jpeg');
