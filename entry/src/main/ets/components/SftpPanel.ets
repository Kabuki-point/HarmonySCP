import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import ssh from 'libentry.so';

const DOWNLOAD_FILE: string = '/payload';

@Component
export struct SftpPanel {
  @Prop connected: boolean = false;
  @State remotePath: string = '';
  @State uploadName: string = '';
  @State message: string = '先选择本地上传文件，连接后填写远端完整路径';
  @State busy: boolean = false;
  @State running: boolean = false;
  @State cancelling: boolean = false;
  @State readyToSave: boolean = false;
  @State bytes: number = 0;
  @State total: number = 0;
  private timer: number = -1;
  private active: boolean = false;
  private uploadUri: string = '';
  private downloadDir: string = '';
  private downloadName: string = '';

  aboutToAppear(): void {
    this.active = true;
    this.timer = setInterval(() => this.refresh(), 200);
  }

  aboutToDisappear(): void {
    this.active = false;
    clearInterval(this.timer);
    if (this.running) ssh.cancelTransfer();
    if (this.downloadDir) this.removeCache(this.downloadDir);
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async removeCache(directory: string): Promise<void> {
    try {
      await fileIo.rmdir(directory);
    } catch {
      // This directory contains only temporary data under the application's cache.
    }
  }

  private async closeFile(file: fileIo.File | undefined): Promise<void> {
    if (!file) return;
    try {
      await fileIo.close(file);
    } catch {
      // Never retry close, as the descriptor may already have been released.
    }
  }

  private async pickUpload(): Promise<void> {
    this.busy = true;
    let file: fileIo.File | undefined;
    try {
      const result = await new picker.DocumentViewPicker(this.context()).select({ maxSelectNumber: 1 });
      if (!this.active || result.length === 0) return;
      file = await fileIo.open(result[0], fileIo.OpenMode.READ_ONLY);
      if (!this.active) return;
      this.uploadName = file.name;
      this.uploadUri = result[0];
      this.message = '已选择上传文件';
    } catch {
      this.message = '无法选择或打开文件，请重试';
    } finally {
      await this.closeFile(file);
      this.busy = false;
    }
  }

  private async start(upload: boolean): Promise<void> {
    const connection = ssh.status();
    const path = this.remotePath;
    const name = path.substring(path.lastIndexOf('/') + 1);
    if (connection.state !== 'connected') {
      this.message = '请先连接并确认服务器身份';
      return;
    }
    if (!path.startsWith('/') || name.length === 0 || name === '.' || name === '..') {
      this.message = '请输入远端完整文件路径，例如 /home/user/test.txt';
      return;
    }
    this.busy = true;
    let file: fileIo.File | undefined;
    let directory: string = '';
    try {
      if (upload) {
        file = await fileIo.open(this.uploadUri, fileIo.OpenMode.READ_ONLY);
      } else {
        directory = await fileIo.mkdtemp(this.context().cacheDir + '/sftp-XXXXXX');
        file = await fileIo.open(directory + DOWNLOAD_FILE, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE);
      }
      if (!this.active) return;
      if (!ssh.startTransfer(upload, file.fd, path, connection.connectionId)) {
        this.message = '无法开始传输，请检查连接状态和远端路径';
        return;
      }
      if (!upload) {
        this.downloadDir = directory;
        this.downloadName = name;
        directory = '';
      }
      this.bytes = 0;
      this.total = 0;
      this.running = true;
      this.refresh();
    } catch {
      this.message = upload ? '无法打开上传文件，请重新选择' : '无法创建下载缓存，请检查剩余存储空间';
    } finally {
      await this.closeFile(file);
      if (directory) await this.removeCache(directory);
      this.busy = false;
    }
  }

  private refresh(): void {
    if (!this.running) return;
    const snapshot = ssh.transferStatus();
    if (this.bytes !== snapshot.bytes) this.bytes = snapshot.bytes;
    if (this.total !== snapshot.total) this.total = snapshot.total;
    const message = this.cancelling && snapshot.state === 'running' ? '正在取消传输…' : snapshot.message;
    if (this.message !== message) this.message = message;
    if (snapshot.state === 'running') return;
    this.running = false;
    this.cancelling = false;
    if (this.downloadDir && !this.readyToSave) {
      if (snapshot.state === 'succeeded') {
        this.readyToSave = true;
      } else {
        this.removeCache(this.downloadDir);
        this.downloadDir = '';
      }
    }
  }

  private discardDownload(): void {
    const directory = this.downloadDir;
    this.downloadDir = '';
    this.readyToSave = false;
    this.removeCache(directory);
  }

  private async saveDownload(): Promise<void> {
    this.busy = true;
    let target: fileIo.File | undefined;
    try {
      const result = await new picker.DocumentViewPicker(this.context()).save({ newFileNames: [this.downloadName] });
      if (!this.active || result.length === 0) return;
      target = await fileIo.open(result[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      await fileIo.copyFile(this.downloadDir + DOWNLOAD_FILE, target.fd);
      const completedFile = target;
      target = undefined;
      await fileIo.close(completedFile);
      this.discardDownload();
      this.message = '文件已保存到设备';
    } catch {
      this.message = '导出失败，可重试。所选位置可能已有部分文件';
    } finally {
      await this.closeFile(target);
      this.busy = false;
    }
  }

  build() {
    Column({ space: 10 }) {
      Text('SFTP 单文件传输').fontSize(17).fontWeight(FontWeight.Bold).width('100%')
      if (this.connected) {
        TextInput({ placeholder: '远端完整路径，例如 /home/user/test.txt', text: this.remotePath })
          .enabled(!this.running && !this.busy)
          .onChange((value: string) => this.remotePath = value)
          .height(48).borderRadius(10).backgroundColor('#F1F5F9')
      }
      Button(this.uploadName ? '重新选择上传文件' : '选择上传文件')
        .width('100%').enabled(!this.busy && !this.running)
        .onClick(() => { this.pickUpload(); })
      if (this.uploadName) {
        Text(this.uploadName).fontSize(13).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      Row({ space: 8 }) {
        Button('上传文件').layoutWeight(1)
          .enabled(this.connected && !!this.uploadName && !this.running && !this.busy)
          .onClick(() => { this.start(true); })
        Button('下载文件').layoutWeight(1)
          .enabled(this.connected && !this.running && !this.busy && !this.readyToSave)
          .onClick(() => { this.start(false); })
      }.width('100%')
      if (this.running) {
        if (this.total > 0) {
          Progress({ value: this.bytes / this.total * 100, total: 100 }).width('100%')
          Text(`${this.bytes} / ${this.total} 字节`).fontSize(12).width('100%')
        }
        Button('取消传输').width('100%').enabled(!this.cancelling).onClick(() => {
          this.cancelling = true;
          ssh.cancelTransfer();
          this.refresh();
        })
      }
      if (this.readyToSave) {
        Text(this.downloadName).fontSize(13).width('100%')
        Row({ space: 8 }) {
          Button('保存下载文件').layoutWeight(1).enabled(!this.busy && !this.running)
            .onClick(() => { this.saveDownload(); })
          Button('丢弃下载').layoutWeight(1).enabled(!this.busy && !this.running).onClick(() => {
            this.discardDownload();
            this.message = '已丢弃下载文件';
          })
        }.width('100%')
      }
      Text(this.message).fontSize(13).lineHeight(21).fontColor('#64748B').width('100%')
    }.padding(22).width('100%').backgroundColor(Color.White).borderRadius(20).margin({ top: 16 })
  }
}
