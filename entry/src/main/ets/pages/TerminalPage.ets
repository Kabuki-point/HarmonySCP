import ssh from 'libentry.so';
import { Utf8Decoder } from '../terminal/TerminalBytes';
import { Terminal } from '../terminal/components/Terminal';
import { TerminalController } from '../terminal/components/TerminalController';
import { TerminalOptions } from '../terminal/models/TerminalOptions';

@Component
export struct TerminalPage {
  @Prop connectionId: number = 0;
  onReturn: () => void = () => {};

  @State private state: string = 'opening';
  @State private message: string = '';
  @State private options: TerminalOptions = TerminalOptions.create();
  private controller: TerminalController = new TerminalController();
  private decoder: Utf8Decoder = new Utf8Decoder();
  private timer: number = -1;

  aboutToAppear(): void {
    this.timer = setInterval(() => this.refresh(), 50);
  }

  aboutToDisappear(): void {
    this.stopPolling();
    if (this.state !== 'closed') {
      ssh.terminalCommand('close', '', 0, 0, this.connectionId);
    }
  }

  private stopPolling(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private refresh(): void {
    const snapshot = ssh.readTerminal(this.connectionId);
    if (this.state !== snapshot.state) {
      this.state = snapshot.state;
      this.message = snapshot.message;
    }
    const text = this.decoder.decode(new Uint8Array(snapshot.output), snapshot.state === 'closed');
    if (text.length > 0) {
      this.controller.write(text);
    }
    if (snapshot.state === 'closed') {
      this.stopPolling();
    }
  }

  private send(data: string): boolean {
    if (this.state !== 'open') {
      return false;
    }
    if (!ssh.terminalCommand('write', data, 0, 0, this.connectionId)) {
      this.message = '输入过长、发送队列已满或连接已断开';
      return false;
    }
    this.message = '';
    return true;
  }

  private statusLabel(): string {
    if (this.message.length > 0) return this.message;
    switch (this.state) {
      case 'open': return '终端已连接';
      case 'closed': return '终端已关闭';
      case 'closing': return '正在关闭终端…';
      default: return '正在打开终端…';
    }
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Button('返回文件页').onClick(() => this.onReturn())
        Text(this.statusLabel()).layoutWeight(1).fontSize(14)
      }.width('100%').padding(12)

      Column() {
        Terminal({
          controller: this.controller,
          options: this.options,
          inputEnabled: this.state === 'open',
          onData: (data: string) => this.send(data),
          onResize: (cols: number, rows: number) => {
            ssh.terminalCommand('resize', '', Math.max(2, Math.min(500, cols)),
              Math.max(2, Math.min(300, rows)), this.connectionId);
          },
          onOptionsChange: (options: TerminalOptions) => { this.options = options; }
        })
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor($r('sys.color.background_primary'))
  }
}
