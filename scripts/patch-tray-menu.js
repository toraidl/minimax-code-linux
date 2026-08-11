#!/usr/bin/env node
// Linux 移植补丁:托盘右键菜单
// 原代码在 Linux 上 setContextMenu(null) + 监听 right-click 事件 —— 这是
// macOS 的模式。Linux 的 StatusNotifier 后端不派发 right-click 事件,右键菜单
// 必须通过 setContextMenu 注册(右键时桌面端通过 DBus ContextMenu 拉取)。
// 幂等:已打过补丁则跳过。
// 用法:node patch-tray-menu.js <asar-extract-dir>
"use strict";
const fs = require("fs");
const path = require("path");

const extractDir = process.argv[2];
if (!extractDir) {
  console.error("用法: node patch-tray-menu.js <asar-extract-dir>");
  process.exit(1);
}

const file = path.join(extractDir, "dist/main/modules/tray/index.js");
if (!fs.existsSync(file)) {
  console.error(`未找到 tray/index.js: ${file}`);
  process.exit(1);
}

let src = fs.readFileSync(file, "utf8");

// 幂等检查:已打过 Linux 补丁
if (src.includes("linux-tray-patch")) {
  console.log("已打过补丁,跳过");
  process.exit(0);
}

const needle = `function applyTrayBehavior(t) {
    t.removeAllListeners('click');
    t.removeAllListeners('right-click');
    t.removeAllListeners('double-click');
    // Don't use setContextMenu — it intercepts left-click on macOS
    t.setContextMenu(null);
    t.on('click', () => {
        (0, window_1.bringToFront)();
    });
    t.on('right-click', () => {
        t.popUpContextMenu(createContextMenu());
    });
}`;

const replacement = `function applyTrayBehavior(t) {
    t.removeAllListeners('click');
    t.removeAllListeners('right-click');
    t.removeAllListeners('double-click');
    if (process.platform === 'linux') {
        // linux-tray-patch:Linux 的 StatusNotifier 后端不派发 right-click 事件,
        // 右键菜单必须通过 setContextMenu 注册(桌面端 DBus ContextMenu 拉取)。
        t.setContextMenu(createContextMenu());
    } else {
        // macOS:setContextMenu 会拦截左键点击,故用 popUpContextMenu + right-click
        t.setContextMenu(null);
        t.on('right-click', () => {
            t.popUpContextMenu(createContextMenu());
        });
    }
    t.on('click', () => {
        (0, window_1.bringToFront)();
    });
}`;

if (!src.includes(needle)) {
  console.error("未找到 applyTrayBehavior 原文,patch 失败(上游代码已变化?)");
  process.exit(1);
}

src = src.replace(needle, replacement);
fs.writeFileSync(file, src);
console.log(`已打补丁: ${file}`);
