import ssh from 'libentry.so';
import { SftpPanel } from '../components/SftpPanel';

@Entry
@Component
struct Index {
  @State nativeAvailable: boolean = false;
  @State host: string = '';
  @State port: string = '22';
  @State username: string = '';
  @State password: string = '';
  @State state: string = 'idle';
  @State message: string = '填写服务器信息，开始安全连接';
  @State fingerprint: string = '';
  @State cancelling: boolean = false;
  private timer: number = -1;
  private lastNativeMessage: string = '';

  aboutToAppear(): void {
    this.refresh();
    this.timer = setInterval(() => this.refresh(), 200);
  }

  aboutToDisappear(): void {
    clearInterval(this.timer);
    ssh.disconnect();
    this.password = '';
  }

  onPageHide(): void {
    this.cancel();
  }

  private refresh(): void {
    const snapshot = ssh.status();
    const stateChanged = this.state !== snapshot.state;
    const wasCancelling = this.cancelling;
    this.nativeAvailable = snapshot.nativeAvailable;
    this.state = snapshot.state;
    this.fingerprint = snapshot.fingerprint;
    if (this.state === 'idle' || this.state === 'error' || this.state === 'preview') {
      this.cancelling = false;
    }
    if ((stateChanged || snapshot.message !== this.lastNativeMessage || wasCancelling !== this.cancelling) &&
      !this.cancelling) {
      this.message = snapshot.message;
    }
    this.lastNativeMessage = snapshot.message;
    // Clear credentials once when a connection ends, so retry input survives later polls.
    if (stateChanged && (this.state === 'connected' || this.state === 'error' || this.state === 'idle')) {
      this.password = '';
    }
  }

  private busy(): boolean {
    return this.nativeAvailable && this.state !== 'idle' && this.state !== 'error';
  }

  private connect(): void {
    if (!this.nativeAvailable) return;
    const numericPort = Number(this.port);
    if (!/^\d+$/.test(this.port) || numericPort < 1 || numericPort > 65535) {
      this.message = '端口应为 1–65535 的整数';
      return;
    }
    if (this.username.trim().length === 0 || this.password.length === 0) {
      this.message = '请输入用户名和密码';
      return;
    }
    if (!ssh.connect(this.host.trim(), numericPort)) {
      this.message = '请输入有效的 IPv4 / IPv6 地址，或等待上次连接结束';
      return;
    }
    this.cancelling = false;
    this.refresh();
  }

  private cancel(): void {
    if (!this.nativeAvailable) return;
    ssh.disconnect();
    this.password = '';
    this.cancelling = true;
    this.message = '正在断开连接…';
  }

  private title(): string {
    if (this.cancelling) return '正在断开';
    switch (this.state) {
      case 'preview': return '预览模式';
      case 'connecting': return '正在连接';
      case 'handshaking': return '安全握手';
      case 'verify': return '核对服务器身份';
      case 'authenticating': return '正在登录';
      case 'connected': return '已安全连接';
      case 'error': return '连接失败';
      default: return '准备连接';
    }
  }

  @Builder
  fieldLabel(text: string) {
    Text(text).fontSize(13).fontWeight(FontWeight.Medium).fontColor('#475569')
      .width('100%').margin({ top: 18, bottom: 8 })
  }

  build() {
    Scroll() {
      Column({ space: 0 }) {
        Row() {
          Text('H').fontSize(22).fontWeight(FontWeight.Bold).fontColor(Color.White)
            .width(44).height(44).textAlign(TextAlign.Center).backgroundColor('#2563EB').borderRadius(14)
          Column({ space: 3 }) {
            Text('HarmonySCP').fontSize(23).fontWeight(FontWeight.Bold).fontColor('#0F172A')
            Text('安全连接，从这里开始').fontSize(12).fontColor('#64748B')
          }.alignItems(HorizontalAlign.Start).margin({ left: 12 })
          Blank()
          Text('MVP 02').fontSize(10).fontWeight(FontWeight.Bold).fontColor('#2563EB')
        }.width('100%').margin({ bottom: 28 })

        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Text('●').fontColor(this.state === 'connected' ? '#16A34A' : '#2563EB').fontSize(12)
            Text(this.title()).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#0F172A')
          }.width('100%')
          Text(this.message).fontSize(13).lineHeight(21).fontColor('#64748B').width('100%')
        }.padding(20).width('100%').backgroundColor('#EFF6FF').borderRadius(18).margin({ bottom: 20 })

        Column() {
          Row() {
            Text('服务器信息').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#0F172A')
            Blank()
            Text('SSH / 密码认证').fontSize(11).fontColor('#64748B')
          }.width('100%')
          this.fieldLabel('服务器 IP 地址')
          TextInput({ placeholder: '例如 192.168.1.10 或 ::1', text: this.host })
            .height(48).borderRadius(10).backgroundColor('#F1F5F9').enabled(this.nativeAvailable && !this.busy())
            .onChange((value: string) => this.host = value)
          this.fieldLabel('端口')
          TextInput({ placeholder: '22', text: this.port }).type(InputType.Number)
            .height(48).borderRadius(10).backgroundColor('#F1F5F9').enabled(this.nativeAvailable && !this.busy())
            .onChange((value: string) => this.port = value)
          this.fieldLabel('用户名')
          TextInput({ placeholder: '输入 SSH 用户名', text: this.username })
            .height(48).borderRadius(10).backgroundColor('#F1F5F9').enabled(this.nativeAvailable && !this.busy())
            .onChange((value: string) => this.username = value)
          this.fieldLabel('密码')
          TextInput({ placeholder: '密码仅用于本次连接', text: this.password }).type(InputType.Password)
            .height(48).borderRadius(10).backgroundColor('#F1F5F9').enabled(this.nativeAvailable && !this.busy())
            .onChange((value: string) => this.password = value)
          if (!this.busy()) {
            Button(this.nativeAvailable ? '连接服务器' : '请在真机或模拟器上运行').width('100%').height(48).borderRadius(12)
              .backgroundColor('#2563EB').enabled(this.nativeAvailable)
              .margin({ top: 24 }).onClick(() => this.connect())
          } else {
            Button(this.state === 'connected' ? '断开连接' : '取消连接')
              .width('100%').height(48).borderRadius(12).backgroundColor('#475569')
              .enabled(!this.cancelling).margin({ top: 24 }).onClick(() => this.cancel())
          }
        }.width('100%').padding(22).backgroundColor(Color.White).borderRadius(20)

        if (this.state === 'verify' && !this.cancelling) {
          Column({ space: 12 }) {
            Text('确认服务器指纹').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#0F172A').width('100%')
            Text('请向服务器管理员核对下方 SHA256 指纹。每次连接都需要确认。')
              .fontSize(13).fontColor('#64748B').lineHeight(21)
            Text(this.fingerprint).fontSize(13).fontFamily('monospace').fontColor('#1D4ED8')
              .copyOption(CopyOptions.InApp).width('100%')
            Button('指纹一致，确认并登录').width('100%').backgroundColor('#2563EB')
              .onClick(() => {
                if (ssh.authenticate(this.username.trim(), this.password, this.fingerprint)) {
                  this.password = '';
                  this.state = 'authenticating';
                  this.message = '正在验证用户名和密码…';
                } else {
                  this.cancel();
                }
              })
            Button('拒绝并断开').width('100%').backgroundColor('#E2E8F0').fontColor('#334155')
              .onClick(() => this.cancel())
          }.padding(22).width('100%').backgroundColor(Color.White).borderRadius(20).margin({ top: 16 })
        }
        if (this.nativeAvailable) {
          SftpPanel({ connected: this.state === 'connected' && !this.cancelling })
        }
        Text('SSH 登录与 SFTP 远程文件管理\n支持 IPv4 / IPv6 · 不保存密码 · 指纹确认限时 2 分钟')
          .fontSize(11).lineHeight(19).fontColor('#64748B').textAlign(TextAlign.Center).margin({ top: 24, bottom: 24 })
      }.width('100%').padding({ left: 20, right: 20, top: 28 })
    }.width('100%').height('100%').backgroundColor('#F8FAFC').align(Alignment.Top)
  }
}
