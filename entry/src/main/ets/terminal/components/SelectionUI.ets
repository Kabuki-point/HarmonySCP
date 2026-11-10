export const HANDLE_WIDTH: number = 18;
export const HANDLE_KNOB: number = 12;
export const MENU_HEIGHT: number = 36;
export const MENU_BTN_MIN_W: number = 48;
export const MENU_RADIUS: number = 18;
export const MENU_HANDLE_PAD: number = 10;
export const SEL_HANDLE_COLOR: string = '#0A59F7';
export const SEL_MENU_BG: string = '#FFFFFF';
export const SEL_MENU_FG: string = '#000000';
export const SEL_FADE_IN_MS: number = 120;
export const SEL_FADE_OUT_MS: number = 100;

/**
 * Selection UI: highlight opacity (via @Link), handles, and action menu.
 * Owns enter / switch / exit / menu-only fade animations.
 */
@Component
export struct SelectionUI {
  /** Parent bumps to present or re-present (switch) with fade. */
  @Prop @Watch('onPresentSeqChange') presentSeq: number = 0;
  /** Parent bumps to dismiss; onDismissed fires after fade-out. */
  @Prop @Watch('onDismissSeqChange') dismissSeq: number = 0;
  /** Parent bumps to hide menu only (drag). */
  @Prop @Watch('onMenuHideSeqChange') menuHideSeq: number = 0;
  /** Parent bumps to show menu only (drag end). */
  @Prop @Watch('onMenuShowSeqChange') menuShowSeq: number = 0;

  @Prop uiMode: string = '';
  @Prop menuHasText: boolean = false;
  @Prop leftHandleVisible: boolean = false;
  @Prop rightHandleVisible: boolean = false;
  @Prop handleH: number = 36;
  @Prop leftHandleX: number = 0;
  @Prop leftHandleY: number = 0;
  @Prop rightHandleX: number = 0;
  @Prop rightHandleY: number = 0;
  @Prop menuPosX: number = 0;
  @Prop menuPosY: number = 0;

  /** Shared with TerminalAtlas selection highlight. */
  @Link selectionOpacity: number;
  @State private menuOpacity: number = 0;
  @State private menuVisible: boolean = false;

  onCut: () => void = () => {};
  onCopy: () => void = () => {};
  onPaste: () => void = () => {};
  onStartHandleMoved: (event: GestureEvent) => void = (_e: GestureEvent) => {};
  onEndHandleMoved: (event: GestureEvent) => void = (_e: GestureEvent) => {};
  onHandlePanEnd: () => void = () => {};
  onDismissed: () => void = () => {};

  private animToken: number = 0;
  private menuToken: number = 0;
  private menuHidePending: boolean = false;
  private dismissing: boolean = false;

  aboutToAppear(): void {
    if (this.presentSeq > 0) {
      this.runPresent();
    }
  }

  onPresentSeqChange(): void {
    if (this.presentSeq <= 0) {
      return;
    }
    this.dismissing = false;
    this.runPresent();
  }

  onDismissSeqChange(): void {
    if (this.dismissSeq <= 0) {
      return;
    }
    this.runDismiss();
  }

  onMenuHideSeqChange(): void {
    if (this.menuHideSeq <= 0) {
      return;
    }
    this.fadeMenuOut();
  }

  onMenuShowSeqChange(): void {
    if (this.menuShowSeq <= 0) {
      return;
    }
    this.fadeMenuIn();
  }

  /** Enter from hidden. Already visible: keep opacity, no switch fade. */
  private runPresent(): void {
    this.menuVisible = true;
    this.menuHidePending = false;
    const token = ++this.animToken;
    this.menuToken++;
    if (this.selectionOpacity >= 0.99) {
      this.selectionOpacity = 1;
      this.menuOpacity = 1;
      return;
    }
    this.selectionOpacity = 0;
    this.menuOpacity = 0;
    this.getUIContext().animateTo({ duration: SEL_FADE_IN_MS, curve: Curve.EaseOut }, () => {
      if (token !== this.animToken) {
        return;
      }
      this.selectionOpacity = 1;
      this.menuOpacity = 1;
    });
  }

  private runDismiss(): void {
    if (this.dismissing) {
      return;
    }
    if (this.selectionOpacity <= 0.01 && this.menuOpacity <= 0.01) {
      this.finishDismiss();
      return;
    }
    this.dismissing = true;
    const token = ++this.animToken;
    this.menuToken++;
    this.getUIContext().animateTo({
      duration: SEL_FADE_OUT_MS,
      curve: Curve.EaseOut,
      onFinish: () => {
        if (token !== this.animToken) {
          return;
        }
        this.finishDismiss();
      }
    }, () => {
      this.selectionOpacity = 0;
      this.menuOpacity = 0;
    });
  }

  private finishDismiss(): void {
    this.dismissing = false;
    this.menuHidePending = false;
    this.menuVisible = false;
    this.selectionOpacity = 0;
    this.menuOpacity = 0;
    this.onDismissed();
  }

  private fadeMenuIn(): void {
    this.menuHidePending = false;
    this.menuVisible = true;
    if (this.menuOpacity >= 0.99) {
      this.menuOpacity = 1;
      return;
    }
    this.menuToken++;
    this.getUIContext().animateTo({ duration: SEL_FADE_IN_MS, curve: Curve.EaseOut }, () => {
      this.menuOpacity = 1;
    });
  }

  private fadeMenuOut(): void {
    if (this.menuHidePending || this.menuOpacity <= 0.01) {
      if (this.menuOpacity <= 0.01) {
        this.menuOpacity = 0;
      }
      return;
    }
    this.menuHidePending = true;
    const token = ++this.menuToken;
    this.getUIContext().animateTo({
      duration: SEL_FADE_OUT_MS,
      curve: Curve.EaseOut,
      onFinish: () => {
        if (token !== this.menuToken) {
          return;
        }
        this.menuHidePending = false;
      }
    }, () => {
      this.menuOpacity = 0;
    });
  }

  @Builder
  LeftHandle() {
    Column() {
      Column()
        .width(HANDLE_KNOB)
        .height(HANDLE_KNOB)
        .borderRadius(HANDLE_KNOB / 2)
        .backgroundColor(Color.White)
        .border({ width: 2, color: SEL_HANDLE_COLOR })
      Column()
        .width(2)
        .layoutWeight(1)
        .backgroundColor(SEL_HANDLE_COLOR)
    }
    .width(HANDLE_WIDTH)
    .height(this.handleH)
    .alignItems(HorizontalAlign.Center)
    .opacity(this.selectionOpacity)
    .position({ x: this.leftHandleX, y: this.leftHandleY })
    .gesture(
      PanGesture()
        .onActionUpdate((event: GestureEvent) => {
          this.onStartHandleMoved(event);
        })
        .onActionEnd(() => {
          this.onHandlePanEnd();
        })
    )
  }

  @Builder
  RightHandle() {
    Column() {
      Column()
        .width(2)
        .layoutWeight(1)
        .backgroundColor(SEL_HANDLE_COLOR)
      Column()
        .width(HANDLE_KNOB)
        .height(HANDLE_KNOB)
        .borderRadius(HANDLE_KNOB / 2)
        .backgroundColor(Color.White)
        .border({ width: 2, color: SEL_HANDLE_COLOR })
    }
    .width(HANDLE_WIDTH)
    .height(this.handleH)
    .alignItems(HorizontalAlign.Center)
    .opacity(this.selectionOpacity)
    .position({ x: this.rightHandleX, y: this.rightHandleY })
    .gesture(
      PanGesture()
        .onActionUpdate((event: GestureEvent) => {
          this.onEndHandleMoved(event);
        })
        .onActionEnd(() => {
          this.onHandlePanEnd();
        })
    )
  }

  @Builder
  ActionMenu() {
    Row({ space: 8 }) {
      if (this.uiMode === 'select' && this.menuHasText) {
        Text('剪切')
          .fontSize(15)
          .fontColor(SEL_MENU_FG)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .height(MENU_HEIGHT)
          .padding({ left: 10, right: 10 })
          .onClick(() => this.onCut())
        Text('复制')
          .fontSize(15)
          .fontColor(SEL_MENU_FG)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .height(MENU_HEIGHT)
          .padding({ left: 10, right: 10 })
          .onClick(() => this.onCopy())
      }
      PasteButton()
        .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
          if (result === PasteButtonOnClickResult.SUCCESS) {
            this.onPaste();
          }
        })
    }
    .height(MENU_HEIGHT)
    .padding({ left: 10, right: 10 })
    .borderRadius(MENU_RADIUS)
    .clip(true)
    .backgroundColor(SEL_MENU_BG)
    .shadow({
      radius: 12,
      color: 'rgba(0,0,0,0.18)',
      offsetX: 0,
      offsetY: 4
    })
    .opacity(this.menuOpacity)
    .hitTestBehavior(this.menuOpacity > 0.5 ? HitTestMode.Default : HitTestMode.None)
    .position({ x: this.menuPosX, y: this.menuPosY })
    .onClick(() => {
    })
  }

  build() {
    Stack() {
      if (this.leftHandleVisible) {
        this.LeftHandle();
      }
      if (this.rightHandleVisible) {
        this.RightHandle();
      }
      if (this.menuVisible) {
        this.ActionMenu();
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}
