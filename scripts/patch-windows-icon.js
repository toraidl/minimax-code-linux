#!/usr/bin/env node
// Linux 移植补丁:给所有 BrowserWindow 加 icon 选项,让窗口/任务栏显示应用图标
// 幂等:已打过补丁则跳过
// 用法:node patch-windows-icon.js <asar-extract-dir> <icon-relative-path>
"use strict";
const fs = require("fs");
const path = require("path");

const extractDir = process.argv[2];
const iconPath = process.argv[3] || "icon.png";
if (!extractDir) {
  console.error("用法: node patch-windows-icon.js <asar-extract-dir> [icon-relative-path]");
  process.exit(1);
}

// 需要打补丁的文件(BrowserWindow 创建点)
const targets = [
  ["dist/main/windows/logViewerWindow.js", "icon"],
  ["dist/main/windows/loginWindow.js", "icon"],
  ["dist/main/windows/onboardingWindow.js", "icon"],
  ["dist/main/windows/archonChatWindow.js", "icon"],
  ["dist/main/windows/archonMiniChatWindow.js", "icon"],
  ["dist/main/modules/ppt-preview/slide-image-renderer.js", "icon"],
];

// icon 路径必须指向真实文件系统(asar 内路径在 Linux 上无法加载):
// 组装时会把 icon.png 放到 <app>/resources/icon.png,process.resourcesPath 即指向它
const iconExpr = (pkgVar) =>
  pkgVar === "path_1"
    ? `path_1.default.join(process.resourcesPath, '${iconPath}')`
    : `path.join(process.resourcesPath, '${iconPath}')`;

let patched = 0;
for (const [relFile, pkgVar] of targets) {
  const file = path.join(extractDir, relFile);
  if (!fs.existsSync(file)) {
    console.log(`跳过(不存在): ${relFile}`);
    continue;
  }
  let src = fs.readFileSync(file, "utf8");
  // 幂等检查:已有 icon 选项
  if (/icon:\s*path/.test(src)) {
    console.log(`已打过补丁: ${relFile}`);
    continue;
  }
  const expr = iconExpr(pkgVar);
  // 在 title 行后插入 icon 选项(所有目标窗口都有 title 字段)
  const lines = src.split("\n");
  let inserted = false;
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^(\s*)title:\s*.+,$/);
    if (m && !inserted) {
      lines.splice(i + 1, 0, `${m[1]}icon: ${expr},`);
      inserted = true;
      break;
    }
  }
  if (!inserted) {
    console.error(`未找到 title 行,跳过: ${relFile}`);
    continue;
  }
  fs.writeFileSync(file, lines.join("\n"));
  console.log(`已打补丁: ${relFile}`);
  patched++;
}
console.log(`完成,共打补丁 ${patched} 个文件`);
