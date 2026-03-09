'use strict';

const chalk = require('chalk');
const ora = require('ora');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { validateRegistryUrl } = require('./utils');

class LocalInstaller {
  constructor(options = {}) {
    this.verbose = false;
    this.dryRun = false;
    this.logger = typeof options.logger === 'function' ? options.logger : () => {};
    this.exitOnFailure = options.exitOnFailure !== undefined ? !!options.exitOnFailure : true;
  }

  async executeCommandLocally(command) {
    if (this.dryRun) {
      const msg = `[DRY-RUN][local] ${command}`;
      console.log(chalk.cyan(msg));
      this.logger('info', msg);
      return '';
    }
    const { spawn } = require('child_process');
    const spinner = ora(`Running: ${command}`).start();
    const spawnOptions = {
      env: { ...process.env, PATH: process.env.PATH || '/usr/local/bin:/usr/bin:/bin' },
      shell: true,
      cwd: process.cwd(),
    };
    this.logger('info', `▶️  ${command}`);
    return new Promise((resolve, reject) => {
      const child = spawn(command, [], spawnOptions);
      let stdoutAll = '';
      let stderrAll = '';
      child.stdout.on('data', (data) => {
        const text = data.toString();
        stdoutAll += text;
        if (this.verbose) process.stdout.write(chalk.gray(text));
        String(text)
          .split('\n')
          .map((l) => l.trim())
          .filter(Boolean)
          .forEach((line) => this.logger('info', line));
      });
      child.stderr.on('data', (data) => {
        const text = data.toString();
        stderrAll += text;
        if (this.verbose) process.stderr.write(chalk.red(text));
        String(text)
          .split('\n')
          .map((l) => l.trim())
          .filter(Boolean)
          .forEach((line) => this.logger('warning', line));
      });
      child.on('close', (code) => {
        if (code === 0) {
          spinner.succeed(`Completed: ${command}`);
          this.logger('success', `✅ Completed: ${command}`);
          resolve(stdoutAll);
        } else {
          spinner.fail(`Failed: ${command} (exit ${code})`);
          const errMsg = stderrAll || `Command failed with exit code ${code}`;
          this.logger('error', `❌ ${errMsg}`);
          reject(new Error(errMsg));
        }
      });
      child.on('error', (err) => {
        spinner.fail(`Error: ${command}`);
        this.logger('error', `❌ ${err.message}`);
        reject(err);
      });
    });
  }

  async installLocal(registry = null) {
    console.log(chalk.blue.bold('🚀 Installing Claude Code locally...\n'));
    try {
      // Node check
      try {
        const isPackaged = process.pkg !== undefined;
        if (isPackaged) {
          const nodeCheckCommand = process.platform === 'win32' ? 'where node.exe' : 'which node';
          const nodePath = await this.executeCommandLocally(nodeCheckCommand);
          const actualNodePath = nodePath.trim().split('\n')[0];
          await this.executeCommandLocally(`"${actualNodePath}" --version`);
          console.log(chalk.green('✅ Node.js is already installed'));
          this.logger('success', '✅ Node.js is already installed');
        } else {
          const nodeCheckCommand = process.platform === 'win32' ? 'where node' : 'which node';
          await this.executeCommandLocally(nodeCheckCommand);
          await this.executeCommandLocally('node --version');
          console.log(chalk.green('✅ Node.js is already installed'));
          this.logger('success', '✅ Node.js is already installed');
        }
      } catch (error) {
        console.log(chalk.red('❌ Node.js is not installed locally'));
        console.log(chalk.yellow('💡 Please install Node.js from https://nodejs.org/'));
        console.log(chalk.gray("   After installing Node.js, make sure it's in your PATH"));
        if (this.exitOnFailure) {
          process.exit(1);
        } else {
          throw error;
        }
      }

      // npm check
      try {
        await this.executeCommandLocally('npm --version');
        console.log(chalk.green('✅ npm is available'));
        this.logger('success', '✅ npm is available');
      } catch (error) {
        console.log(chalk.red('❌ npm is not available'));
        console.log(chalk.yellow('💡 Please ensure npm is installed with Node.js'));
        if (this.exitOnFailure) {
          process.exit(1);
        } else {
          throw error;
        }
      }

      const validatedRegistry = validateRegistryUrl(registry);
      const registryArg = validatedRegistry ? ` --registry="${validatedRegistry}"` : '';
      await this.executeCommandLocally(`npm install -g @anthropic-ai/claude-code${registryArg}`);
      await this.executeCommandLocally(`npm install -g @musistudio/claude-code-router${registryArg}`);

      await this.executeCommandLocally('claude --version');
      await this.executeCommandLocally('ccr -v');

      console.log(chalk.green.bold('\n✅ Claude Code installed successfully on your computer!'));
      console.log(chalk.cyan('🎉 You can now use `claude` and `ccr` commands locally.'));
      console.log(chalk.blue('\nℹ️  Tip: You can configure default models via `ccr ui` or by editing ~/.claude-code-router/config.json'));
      // First-time setup guidance if user is stuck at Claude login when running `ccr code`
      console.log(chalk.yellow('\n💡 First-time tip: If `ccr code` gets stuck on the Claude login screen, run this once:'));
      console.log(chalk.cyan('   ANTHROPIC_AUTH_TOKEN=token claude'));
      console.log(chalk.gray('   Then exit the `claude` CLI and run `ccr code` again.'));
      this.logger('info', '💡 First-time tip: If `ccr code` gets stuck on the Claude login screen, run: ANTHROPIC_AUTH_TOKEN=token claude; exit, then run `ccr code` again.');
      this.logger('success', '🎉 Local installation completed successfully');
    } catch (error) {
      console.error(chalk.red.bold('\n❌ Local installation failed:'), error.message);
      this.logger('error', `❌ Local installation failed: ${error.message}`);
      if (this.exitOnFailure) {
        process.exit(1);
      } else {
        throw error;
      }
    }
  }

  async generateMultiProviderConfig(providers, preferredModel = null) {
    const configDir = path.join(os.homedir(), '.claude-code-router');
    const configPath = path.join(configDir, 'config.json');

    if (!providers || providers.length === 0) {
      throw new Error('No providers specified');
    }

    try {
      console.log(chalk.blue('🔍 Generating configuration...'));
      this.logger('info', '🔍 Generating configuration...');

      const allProviders = [];
      let defaultProvider = null;

      for (const provider of providers) {
        // models are always explicitly provided by the caller
        const models = provider.models || [];

        allProviders.push({
          name: provider.name,
          api_base_url: `${provider.apiUrl}/v1/messages`,
          api_key: provider.apiKey,
          models: models,
          transformer: { use: ['Anthropic'] }
        });

        if (!defaultProvider) {
          const m = preferredModel && models.includes(preferredModel) ? preferredModel : models[0];
          if (m) defaultProvider = `${provider.name},${m}`;
        }

        console.log(chalk.green(`✅ Configured ${provider.name}: ${models.length} model(s)`));
        this.logger('success', `✅ Configured ${provider.name}: ${models.length} model(s)`);
      }

      const Router = {
        default: defaultProvider,
        background: defaultProvider,
        think: defaultProvider,
        longContext: defaultProvider,
        longContextThreshold: 60000,
        webSearch: defaultProvider,
      };

      const config = {
        LOG: false,
        CLAUDE_PATH: '',
        HOST: '127.0.0.1',
        PORT: 3456,
        APIKEY: providers[0].apiKey,
        API_TIMEOUT_MS: '600000',
        PROXY_URL: '',
        Transformers: [],
        Providers: allProviders,
        Router,
      };

      if (!fs.existsSync(configDir)) fs.mkdirSync(configDir, { recursive: true });
      fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
      console.log(chalk.green(`✅ Config generated at: ${configPath}`));
      this.logger('success', `✅ Config generated at: ${configPath}`);
    } catch (error) {
      console.error(chalk.red('❌ Failed to generate config:'), error.message);
      this.logger('error', `❌ Failed to generate config: ${error.message}`);
      throw error;
    }
  }
}

module.exports = { LocalInstaller };

