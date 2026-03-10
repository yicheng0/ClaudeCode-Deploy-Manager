'use strict';

const chalk = require('chalk');
const readline = require('readline');
const { ClaudeRemoteInstaller } = require('./installer');
const { LocalInstaller } = require('./local');
const packageJson = require('../package.json');

// 部署方式说明：
// - "SSH 远程服务器"：适用于有 SSH 访问权限的 VPS/云服务器
//   需要提供：服务器 IP、用户名、密码或密钥文件
// - "本地安装"：适用于腾讯云 Web 终端、WorkSpace、已通过其他方式
//   登录到服务器的场景，直接在当前机器上执行安装

const API_BASE_URL = 'https://breakout.wenwen-ai.com';
const PROVIDER_NAME = 'anthropic';

// 默认模型列表
const DEFAULT_MODELS = [
  { name: 'claude-sonnet-4-6-20260218', label: 'claude-sonnet-4-6-20260218（推荐，速度快）' },
  { name: 'claude-opus-4-6-20260205', label: 'claude-opus-4-6-20260205（更强，较慢）' }
];

/**
 * 普通文本输入
 */
async function ask(prompt) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(prompt, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

/**
 * 掩码密码输入
 */
async function askPassword(prompt) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const muteOutput = (stream, mute) => {
    const write = stream.write;
    stream.write = function (string, encoding, fd) {
      if (mute) return true;
      return write.apply(stream, [string, encoding, fd]);
    };
    return () => (stream.write = write);
  };
  const unmute = muteOutput(process.stdout, true);
  const password = await new Promise((resolve) => {
    rl.question(prompt, (answer) => {
      unmute();
      rl.close();
      console.log();
      resolve(answer);
    });
  });
  return password;
}

/**
 * 数字选择菜单
 */
async function askChoice(prompt, options) {
  console.log(chalk.cyan(`\n${prompt}`));
  options.forEach((opt, idx) => {
    console.log(chalk.gray(`  ${idx + 1}) ${opt}`));
  });

  while (true) {
    const answer = await ask(chalk.cyan('请选择 (输入数字): '));
    const choice = parseInt(answer);
    if (choice >= 1 && choice <= options.length) {
      return choice;
    }
    console.log(chalk.red('无效选择，请重新输入'));
  }
}

/**
 * SSH 认证方式询问
 */
async function askSshAuth() {
  const authChoice = await askChoice('认证方式', ['密码', '密钥文件', 'SSH Agent']);

  if (authChoice === 1) {
    const password = await askPassword('? 密码（输入时不显示）: ');
    return { password };
  } else if (authChoice === 2) {
    const keyPath = await ask('? 密钥文件路径: ');
    const passphrase = await askPassword('? 密钥密码（如无密码直接回车）: ');
    return { privateKey: keyPath, passphrase: passphrase || undefined };
  } else {
    return { agent: process.env.SSH_AUTH_SOCK };
  }
}

/**
 * 主 CLI 入口
 */
async function runCli() {
  console.log(chalk.bgBlue.white.bold('\n  问问 AI - Claude Code 一键部署脚本  '));
  console.log(chalk.cyan('━'.repeat(50)));
  console.log(chalk.white('  本脚本由 问问AI (breakout.wenwen-ai.com) 提供'));
  console.log(chalk.white('  使用专属 API 端点，无需自备 Anthropic 账号'));
  console.log(chalk.white('  支持 SSH 远程部署 和 本地直接安装两种方式'));
  console.log(chalk.cyan('━'.repeat(50)));
  console.log(chalk.gray(`\n版本: ${packageJson.version}  |  API: ${API_BASE_URL}\n`));

  // 1. 选择部署方式
  const mode = await askChoice('请选择部署方式', [
    'SSH 远程服务器（适用于有 SSH 访问权限的服务器）',
    '本地安装（适用于腾讯云 Web 终端、已登录的服务器等无需 SSH 的场景）'
  ]);

  let sshConfig = null;

  // 2. 如果是 SSH 模式，询问服务器信息
  if (mode === 1) {
    console.log(chalk.cyan('\n--- SSH 服务器配置 ---'));
    const host = await ask('? 服务器地址 (host): ');
    const username = await ask('? 用户名: ');
    const port = await ask('? SSH 端口 (默认 22): ') || '22';
    const auth = await askSshAuth();

    sshConfig = { host, username, port, auth };
  }

  // 3. 询问 API Key
  console.log(chalk.cyan('\n--- API 配置 ---'));
  const apiKey = await askPassword('? 请输入 API Key: ');

  // 4. 选择模型
  const modelOptions = [
    ...DEFAULT_MODELS.map(m => m.label),
    '手动输入其他模型名'
  ];
  const modelChoice = await askChoice('请选择默认模型', modelOptions);

  let model;
  if (modelChoice <= DEFAULT_MODELS.length) {
    model = DEFAULT_MODELS[modelChoice - 1].name;
  } else {
    model = await ask('? 请输入模型名: ');
  }

  // 5. 构建 provider 配置
  const providers = [{
    name: PROVIDER_NAME,
    apiKey,
    apiUrl: API_BASE_URL,
    models: [model]
  }];

  console.log(chalk.green('\n✅ 配置完成，开始安装...\n'));

  // 6. 执行安装
  try {
    if (mode === 2) {
      // 本地安装
      const installer = new LocalInstaller({ exitOnFailure: true });
      await installer.generateMultiProviderConfig(providers, model);
      await installer.installLocal();
      console.log(chalk.green.bold('\n✅ 本地安装完成！'));
    } else {
      // SSH 远程安装
      const installer = new ClaudeRemoteInstaller({ exitOnFailure: true });
      await installer.installRemoteWithProviders(
        sshConfig.host,
        sshConfig.username,
        sshConfig.auth,
        parseInt(sshConfig.port),
        false, // skipConfig
        null,  // registry
        providers,
        false, // userInstall
        model
      );
      console.log(chalk.green.bold('\n✅ 远程安装完成！'));
    }

    console.log(chalk.gray('\n如遇到 "command not found"，请确保 PATH 包含全局 npm 二进制目录：'));
    console.log(chalk.gray('  echo "export PATH=$(npm prefix -g)/bin:$PATH" >> ~/.bashrc && source ~/.bashrc'));
  } catch (error) {
    console.error(chalk.red('\n❌ 安装失败:'), error.message);
    process.exit(1);
  }
}

module.exports = { runCli };
