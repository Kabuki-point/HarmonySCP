import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import ssh, { RemoteEntry } from 'libentry.so';

const DOWNLOAD_FILE: string = '/payload';

@Component
export struct SftpPanel {
  @Prop connected: boolean = false;
  @State directory: string = '';
  @State pathInput: string = '.';
  @State entries: RemoteEntry[] = [];
  @State selected: RemoteEntry | undefined = undefined;
  @State listing: boolean = false;
  @State listMessage: string = '';
  @State operationMessage: string = '';
  @State editor: string = '';
  @State nameInput: string = '';
  @State hasUpload: boolean = false;
  @State uploadName: string = '';
  @State message: string = '登录后浏览远程文件。上传也可在连接前选好本地文件';
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
  private browserConnection: number = -1;
  private remoteAction: string = '';
  private uploadDirectory: string = '';

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
      this.hasUpload = true;
      this.uploadUri = result[0];
      this.message = '已选择上传文件';
    } catch {
      this.message = '无法选择或打开文件，请重试';
    } finally {
      await this.closeFile(file);
      this.busy = false;
    }
  }

  private childPath(name: string): string {
    return this.directory === '/' ? '/' + name : this.directory + '/' + name;
  }

  private validName(name: string): boolean {
    return name.length > 0 && name !== '.' && name !== '..' && !name.includes('/') && !name.includes('\u0000');
  }

  private blocked(): boolean {
    return this.running || this.busy || this.listing;
  }

  private requestRemote(action: string, path: string, name: string = ''): void {
    if (!this.connected || this.blocked()) return;
    if (!ssh.startRemote(action, path, name, this.browserConnection)) {
      this.operationMessage = '无法开始远端操作，请检查路径、连接状态后重试';
      return;
    }
    this.remoteAction = action;
    this.listing = true;
  }

  private navigate(path: string): void {
    if (path !== '.' && !path.startsWith('/')) {
      this.operationMessage = '请输入以 / 开头的目录路径，或输入 . 返回登录目录';
      return;
    }
    this.editor = '';
    this.operationMessage = '';
    this.requestRemote('list', path);
  }

  private refreshBrowser(): void {
    const connection = ssh.status();
    if (!this.connected || connection.state !== 'connected') {
      if (this.browserConnection !== -1) {
        if (this.listing) {
          const result = ssh.remoteStatus();
          this.message = result.state === 'running' ? '连接已断开，请重新连接并刷新目录核对结果' : result.message;
        }
        this.browserConnection = -1;
        this.directory = '';
        this.pathInput = '.';
        this.entries = [];
        this.selected = undefined;
        this.listing = false;
        this.editor = '';
        this.listMessage = '';
        this.operationMessage = '';
      }
      return;
    }
    if (this.browserConnection !== connection.connectionId) {
      if (this.blocked()) return;
      this.browserConnection = connection.connectionId;
      this.navigate('.');
      return;
    }
    if (!this.listing) return;
    const result = ssh.remoteStatus();
    if (result.state === 'running') return;
    this.listing = false;
    if (result.state !== 'succeeded') {
      this.operationMessage = result.message;
      return;
    }
    this.selected = undefined;
    if (this.remoteAction === 'list') {
      this.directory = result.path;
      this.pathInput = result.path;
      this.entries = result.entries;
      this.listMessage = result.message;
    } else {
      this.operationMessage = result.message;
      this.entries = [];
      this.listMessage = '';
      this.requestRemote('list', this.directory);
    }
  }

  private submitEdit(): void {
    const entry = this.selected;
    if (this.editor === 'delete') {
      if (entry) this.requestRemote(entry.kind === 'directory' ? 'rmdir' : 'unlink', this.childPath(entry.name));
    } else {
      if (!this.validName(this.nameInput)) {
        this.operationMessage = '请输入单个有效名称，名称不能包含 /';
        return;
      }
      if (this.editor === 'mkdir') {
        this.requestRemote('mkdir', this.childPath(this.nameInput));
      } else if (entry) {
        if (entry.name === this.nameInput) {
          this.editor = '';
          return;
        }
        this.requestRemote('rename', this.childPath(entry.name), this.nameInput);
      }
    }
    if (this.listing) this.editor = '';
  }

  private entryInfo(entry: RemoteEntry): string {
    let label = entry.kind === 'directory' ? '文件夹' :
      (entry.kind === 'file' ? '文件' : (entry.kind === 'link' ? '符号链接' : '其他类型'));
    if (entry.kind === 'file' && entry.size >= 0) label += ' · ' + entry.size.toString() + ' 字节';
    if (entry.modified >= 0) label += ' · ' + new Date(entry.modified * 1000).toLocaleString();
    return label;
  }

  private async start(upload: boolean, name: string): Promise<void> {
    const connection = ssh.status();
    const path = this.childPath(name);
    if (connection.state !== 'connected' || connection.connectionId !== this.browserConnection) {
      this.message = '请先连接并确认服务器身份';
      return;
    }
    if (!this.directory || !this.validName(name)) {
      this.message = '请确认当前目录和文件名';
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
      this.uploadDirectory = upload ? this.directory : '';
      if (!upload) {
        this.downloadDir = directory;
        this.downloadName = name;
        directory = '';
      }
      this.bytes = 0;
      this.total = 0;
      this.running = true;
    } catch {
      this.message = upload ? '无法打开上传文件，请重新选择' : '无法创建下载缓存，请检查剩余存储空间';
    } finally {
      await this.closeFile(file);
      if (directory) await this.removeCache(directory);
      this.busy = false;
    }
  }

  private refresh(): void {
    this.refreshBrowser();
    if (!this.running || this.busy) return;
    const snapshot = ssh.transferStatus();
    if (this.bytes !== snapshot.bytes) this.bytes = snapshot.bytes;
    if (this.total !== snapshot.total) this.total = snapshot.total;
    const message = this.cancelling && snapshot.state === 'running' ? '正在取消传输…' : snapshot.message;
    if (this.message !== message) this.message = message;
    if (snapshot.state === 'running') return;
    this.running = false;
    this.cancelling = false;
    if (snapshot.state === 'succeeded' && this.uploadDirectory === this.directory && this.uploadDirectory) {
      this.requestRemote('list', this.directory);
    }
    this.uploadDirectory = '';
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

  @Builder
  remoteBrowser() {
    Column({ space: 8 }) {
      TextInput({ placeholder: '远端目录路径，或 .', text: this.pathInput })
        .enabled(!this.blocked() && !this.editor)
        .onChange((value: string) => this.pathInput = value)
      Row({ space: 6 }) {
        Button('前往').layoutWeight(1).enabled(!this.blocked() && !this.editor)
          .onClick(() => this.navigate(this.pathInput))
        Button('上一级').layoutWeight(1)
          .enabled(!this.blocked() && !this.editor && this.directory.length > 1)
          .onClick(() => this.navigate(this.directory.substring(0, this.directory.lastIndexOf('/')) || '/'))
        Button('刷新').layoutWeight(1).enabled(!this.blocked() && !this.editor)
          .onClick(() => this.navigate(this.directory || this.pathInput))
      }.width('100%')
      if (this.directory) {
        Text(this.directory).width('100%').fontWeight(FontWeight.Medium).copyOption(CopyOptions.InApp)
        if (this.entries.length > 0) {
          List({ space: 3 }) {
            ForEach(this.entries, (entry: RemoteEntry) => {
              ListItem() {
                Column({ space: 4 }) {
                  Text(entry.name).fontSize(14).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(this.entryInfo(entry)).fontSize(11).fontColor('#64748B')
                }.width('100%').alignItems(HorizontalAlign.Start).padding(8)
                  .backgroundColor(this.selected?.name === entry.name ? '#DBEAFE' : '#F8FAFC')
                  .borderRadius(8)
                  .onClick(() => {
                    if (!this.blocked() && !this.editor) this.selected = entry;
                  })
                }
            }, (entry: RemoteEntry) => entry.name + '|' + entry.kind + '|' + entry.size + '|' + entry.modified)
          }.width('100%').height(Math.min(300, this.entries.length * 58))
            .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
        }
        Button('新建文件夹').width('100%').enabled(!this.blocked() && !this.editor)
          .onClick(() => { this.nameInput = ''; this.editor = 'mkdir'; })
        if (this.selected && (this.selected.kind === 'file' || this.selected.kind === 'directory')) {
          Text(this.selected.name).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: 6 }) {
            if (this.selected.kind === 'file') {
              Button('下载文件').layoutWeight(1).enabled(!this.blocked() && !this.editor && !this.readyToSave)
                .onClick(() => { if (this.selected) this.start(false, this.selected.name); })
            } else {
              Button('打开文件夹').layoutWeight(1).enabled(!this.blocked() && !this.editor)
                .onClick(() => { if (this.selected) this.navigate(this.childPath(this.selected.name)); })
            }
            Button('重命名').layoutWeight(1).enabled(!this.blocked() && !this.editor)
              .onClick(() => { this.nameInput = this.selected?.name ?? ''; this.editor = 'rename'; })
            Button('删除').layoutWeight(1).enabled(!this.blocked() && !this.editor)
              .onClick(() => { this.editor = 'delete'; })
          }.width('100%')
        }
        if (this.editor) {
          if (this.editor === 'delete') {
            Text(this.selected?.kind === 'directory' ?
              '删除空文件夹「' + this.selected.name + '」？' :
              '删除文件「' + (this.selected?.name ?? '') + '」？').width('100%')
          } else {
            TextInput({ placeholder: '输入名称', text: this.nameInput })
              .onChange((value: string) => this.nameInput = value)
          }
          Row({ space: 6 }) {
            Button(this.editor === 'delete' ? '确认删除' : '确认').layoutWeight(1)
              .enabled(!this.blocked()).onClick(() => this.submitEdit())
            Button('取消').layoutWeight(1).onClick(() => { this.editor = ''; })
          }.width('100%')
        }
      }
      if (this.listing || this.listMessage) {
        Text(this.listing ? '正在处理远端请求…' : this.listMessage).fontSize(12).width('100%')
      }
      if (this.operationMessage) Text(this.operationMessage).fontSize(13).width('100%')
    }.width('100%')
  }

  build() {
    Column({ space: 10 }) {
      Text('SFTP 远程文件').fontSize(17).fontWeight(FontWeight.Bold).width('100%')
      if (this.connected) this.remoteBrowser()
      Button(this.hasUpload ? '重新选择上传文件' : '选择上传文件')
        .width('100%').enabled(!this.blocked() && !this.editor)
        .onClick(() => { this.pickUpload(); })
      if (this.hasUpload) {
        TextInput({ placeholder: '上传文件名', text: this.uploadName })
          .enabled(!this.blocked() && !this.editor)
          .onChange((value: string) => this.uploadName = value)
        if (this.connected && this.directory) {
          Button('上传到当前目录').width('100%').enabled(!this.blocked() && !this.editor)
            .onClick(() => { this.start(true, this.uploadName); })
        }
      }
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
