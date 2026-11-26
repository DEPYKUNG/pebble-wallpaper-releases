#import "PebbleAppInternal.h"

@implementation PebbleApp (Settings)

- (void)showSettings:(id)sender {
    if (!self.settings) [self buildSettings];
    [NSApp activateIgnoringOtherApps:YES];
    [self.settings makeKeyAndOrderFront:nil];
}

- (void)buildSettings {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 840, 580)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable |
                  NSWindowStyleMaskFullSizeContentView
          backing:NSBackingStoreBuffered defer:NO];
    window.title = @"鹅卵石设置";
#if __has_include(<Sparkle/Sparkle.h>)
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsDidClose:)
        name:NSWindowWillCloseNotification object:window];
#endif
    window.titlebarAppearsTransparent = YES;
    window.releasedWhenClosed = NO;
    window.minSize = NSMakeSize(760, 520);

    window.opaque = NO;
    window.backgroundColor = NSColor.clearColor;

    BOOL preview = self.settingsPreview || self.shotPath;
    NSArray *arguments = NSProcessInfo.processInfo.arguments;
    if (preview && [arguments containsObject:@"--preview-dark"]) window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    if (preview && [arguments containsObject:@"--preview-light"]) window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    if (self.settingsPreview) window.title = @"鹅卵石设置 · 开发预览";
    PebbleSettingsSurface *surface = [[PebbleSettingsSurface alloc] initWithFrame:window.contentView.bounds
        preferFrosted:preview && [arguments containsObject:@"--preview-frosted"]
        forceSolid:preview && [arguments containsObject:@"--preview-solid"]];
    [self pin:surface into:window.contentView inset:0];

    NSView *sidebar = [NSView new];
    sidebar.translatesAutoresizingMaskIntoConstraints = NO;

    self.sectionButtons = [NSMutableArray array];
    NSArray *sections = @[@[@"通用", @"settings"], @[@"桌宠", @"smile"], @[@"收藏", @"heart"], @[@"石头证", @"id-badge"], @[@"关于", @"info"]];
    NSStackView *list = [NSStackView stackViewWithViews:@[]];
    list.orientation = NSUserInterfaceLayoutOrientationVertical;
    list.alignment = NSLayoutAttributeLeading;
    list.spacing = 9;
    list.edgeInsets = NSEdgeInsetsMake(12, 10, 12, 10);
    list.translatesAutoresizingMaskIntoConstraints = NO;
    [sections enumerateObjectsUsingBlock:^(NSArray *section, NSUInteger index, BOOL *stop) {
        NSButton *row = [NSButton buttonWithTitle:section[0] target:self
                                           action:@selector(selectSection:)];
        row.image = [self settingsIcon:section[1]];
        row.imagePosition = NSImageLeft;
        row.bordered = NO;
        row.alignment = NSTextAlignmentLeft;
        row.font = [NSFont systemFontOfSize:13];
        row.tag = (NSInteger)index;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        // A box behind the button gives the rounded selection without the heavy
        // slab a recessed bezel paints, and follows light and dark on its own.
        PebbleRoundedView *seat = [self roundedViewFilled:NSColor.clearColor radius:6];
        [self pin:row into:seat inset:4];
        [list addArrangedSubview:seat];
        [seat.widthAnchor constraintEqualToAnchor:list.widthAnchor constant:-20].active = YES;
        [self.sectionButtons addObject:row];
    }];
    [sidebar addSubview:list];

    self.panes = @[[self generalPane], [self petPane], [NSView new], [NSView new], [self aboutPane]];
    NSView *body = [NSView new];
    body.translatesAutoresizingMaskIntoConstraints = NO;
    self.settingsBody = body;

    NSView *root = surface.contentView;
    [root addSubview:sidebar];
    [root addSubview:body];
    NSLayoutGuide *content = window.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [sidebar.topAnchor constraintEqualToAnchor:content.topAnchor],
        [sidebar.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [sidebar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [sidebar.widthAnchor constraintEqualToConstant:196],
        [list.topAnchor constraintEqualToAnchor:sidebar.topAnchor],
        [list.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor],
        [list.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [body.topAnchor constraintEqualToAnchor:content.topAnchor],
        [body.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [body.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [body.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
    ]];

    // Remembers where the user left it, which a settings window is expected to do.
    if (!self.settingsPreview && !self.shotPath && !self.testPreviewPath && !self.petPreview) [window setFrameAutosaveName:@"PebbleSettingsWindow"];
    if (NSIsEmptyRect(window.frame) || !window.frameAutosaveName.length) [window center];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsWillClose:)
                 name:NSWindowWillCloseNotification object:window];
    self.settings = window;
    [self showPaneAtIndex:0];
}

- (void)selectSection:(NSButton *)sender {
    [self showPaneAtIndex:sender.tag];
}

- (void)showPaneAtIndex:(NSInteger)index {
    self.selectedSettingsPane = index;
    for (NSButton *button in self.sectionButtons) {
        PebbleRoundedView *seat = (PebbleRoundedView *)button.superview;
        if ([seat isKindOfClass:PebbleRoundedView.class]) {
            seat.fill = button.tag == index ?
                NSColor.unemphasizedSelectedContentBackgroundColor : NSColor.clearColor;
        }
    }
    // Keep the panes alive so the pass card keeps its stone across tab changes.
    for (NSView *view in self.settingsBody.subviews.copy) [view removeFromSuperview];
    NSView *pane = index == FavoritesPaneIndex ? [self favoritesPane] :
        (index == PassPaneIndex ? [self passPane] : self.panes[index]);
    pane.translatesAutoresizingMaskIntoConstraints = NO;
    [self.settingsBody addSubview:pane];
    [NSLayoutConstraint activateConstraints:@[
        [pane.topAnchor constraintEqualToAnchor:self.settingsBody.topAnchor],
        [pane.bottomAnchor constraintEqualToAnchor:self.settingsBody.bottomAnchor],
        [pane.leadingAnchor constraintEqualToAnchor:self.settingsBody.leadingAnchor],
        [pane.trailingAnchor constraintEqualToAnchor:self.settingsBody.trailingAnchor],
    ]];
}

- (NSView *)stageAround:(NSView *)view height:(CGFloat)height {
    [view.heightAnchor constraintEqualToConstant:height].active = YES;
    // The wallpaper's own paper colour, so the stone sits on its usual ground.
    PebbleRoundedView *stage = [self roundedViewFilled:
        [NSColor colorWithSRGBRed:238.0/255 green:238.0/255 blue:231.0/255 alpha:1] radius:10];
    [self pin:view into:stage inset:0];
    return stage;
}

- (void)selectBackground:(NSButton *)sender {
    NSUInteger index = (NSUInteger)sender.tag;
    if (index >= BackgroundCount) return;
    self.backgroundPreset = @(BackgroundKeys[index]);
    if (![self syncNativeDesktopBackground:NO explicitChange:YES])
        [self showWallpaperError:@"系统壁纸背景暂时未能同步，请稍后重新选择背景。"];
    if (!self.testPreviewPath) {
        [NSUserDefaults.standardUserDefaults setObject:self.backgroundPreset forKey:BackgroundPreference];
    }
    for (NSButton *button in self.backgroundButtons) {
        button.state = button == sender ? NSControlStateValueOn : NSControlStateValueOff;
        NSString *label = BackgroundLabels[button.tag];
        button.title = button == sender ? [label stringByAppendingString:@" ✓"] : label;
    }
    [self syncRendererStartupScripts];
    NSString *script = [self.backgroundConfigScript stringByAppendingString:@"window.pebbleRedraw?.();"];
    [self forEachRenderer:^(WKWebView *web) {
        [self performWallpaperScript:script inWeb:web reportErrors:YES completion:nil];
    }];
}

- (NSView *)backgroundPicker {
    self.backgroundButtons = [NSMutableArray array];
    NSStackView *choices = [NSStackView stackViewWithViews:@[]];
    choices.orientation = NSUserInterfaceLayoutOrientationVertical;
    choices.alignment = NSLayoutAttributeLeading;
    choices.spacing = 4;
    NSStackView *row = nil;
    for (NSUInteger index = 0; index < BackgroundCount; index++) {
        if (index % 4 == 0) {
            row = [NSStackView stackViewWithViews:@[]];
            row.distribution = NSStackViewDistributionFillEqually;
            row.spacing = 8;
            [choices addArrangedSubview:row];
            [row.widthAnchor constraintEqualToAnchor:choices.widthAnchor].active = YES;
        }
        NSString *key = @(BackgroundKeys[index]);
        NSUInteger rgb = BackgroundColors[index];
        NSColor *color = [NSColor colorWithSRGBRed:((rgb >> 16) & 255) / 255.0
                                            green:((rgb >> 8) & 255) / 255.0
                                             blue:(rgb & 255) / 255.0 alpha:1];
        NSURL *textureURL = [NSBundle.mainBundle URLForResource:[@"background-" stringByAppendingString:key] withExtension:@"jpg"];
        NSImage *texture = textureURL ? [[NSImage alloc] initWithContentsOfURL:textureURL] : nil;
        NSImage *thumbnail = [NSImage imageWithSize:NSMakeSize(96, 43) flipped:NO drawingHandler:^BOOL(NSRect rect) {
            [color setFill];
            NSBezierPath *swatch = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:5 yRadius:5];
            [swatch fill];
            if (texture) {
                [NSGraphicsContext saveGraphicsState];
                [swatch addClip];
                [texture drawInRect:rect fromRect:NSMakeRect(0,0,288,129)
                          operation:NSCompositingOperationSourceOver fraction:1];
                [NSGraphicsContext restoreGraphicsState];
            }
            return YES;
        }];
        NSButton *choice = [NSButton buttonWithTitle:BackgroundLabels[index] image:thumbnail
                                            target:self action:@selector(selectBackground:)];
        [choice setButtonType:NSButtonTypePushOnPushOff];
        choice.bordered = NO;
        choice.accessibilityLabel = BackgroundLabels[index];
        choice.imagePosition = NSImageAbove;
        choice.imageScaling = NSImageScaleNone;
        choice.tag = index;
        choice.state = [key isEqualToString:self.backgroundPreset] ? NSControlStateValueOn : NSControlStateValueOff;
        if (choice.state == NSControlStateValueOn) choice.title = [choice.title stringByAppendingString:@" ✓"];
        [choice.heightAnchor constraintEqualToConstant:64].active = YES;
        [row addArrangedSubview:choice];
        [self.backgroundButtons addObject:choice];
    }
    return [self settingsGroup:@"桌面背景" containing:choices];
}

- (NSView *)settingsGroup:(NSString *)name containing:(NSView *)choices {
    NSTextField *title = [NSTextField labelWithString:name];
    title.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    NSStackView *group = [NSStackView stackViewWithViews:@[title, choices]];
    group.orientation = NSUserInterfaceLayoutOrientationVertical;
    group.alignment = NSLayoutAttributeLeading;
    group.spacing = 8;
    [choices.widthAnchor constraintEqualToAnchor:group.widthAnchor].active = YES;
    return group;
}

- (NSView *)generalPane {
    self.texturePopUp = [self popUpWithKeys:PebbleTextureKeys labels:PebbleTextureLabels
        count:PebbleTextureCount selected:self.texture action:@selector(selectTexture:)];
    self.palettePopUp = [self popUpWithKeys:PebbleColorKeys labels:PebbleColorLabels
        count:PebbleColorCount selected:self.palette action:@selector(selectPalette:)];
    self.facePopUp = [self popUpWithKeys:PebbleFaceKeys labels:PebbleFaceLabels
        count:PebbleFaceCount selected:self.face action:@selector(selectFace:)];
    self.rotationSwitch = [self switchOn:!self.paused action:@selector(togglePause:)];

    NSView *stone = [self cardWithRows:@[
        [self rowWithSymbol:@"repeat" title:@"换一颗鹅卵石"
                   subtitle:nil
                    control:[self actionButton:@"换一颗" action:@selector(changePebble:)]],
        [self rowWithSymbol:@"grid" title:@"材质"
                   subtitle:nil control:self.texturePopUp],
        [self rowWithSymbol:@"palette" title:@"颜色"
                   subtitle:nil control:self.palettePopUp],
        [self rowWithSymbol:@"smile" title:@"脸孔"
                   subtitle:nil
                    control:self.facePopUp],
        [self rowWithSymbol:@"repeat" title:ReloadWallpaperTitle subtitle:nil
                    control:[self actionButton:@"重新加载" action:@selector(reloadRenderers:)]],
    ]];
    self.tiltSlider = [NSSlider sliderWithValue:self.tiltDegrees minValue:-TiltLimit maxValue:TiltLimit
                                         target:self action:@selector(selectTilt:)];
    self.tiltSlider.continuous = YES;
    self.tiltSlider.accessibilityLabel = @"倾斜角度";
    [self.tiltSlider.widthAnchor constraintEqualToConstant:120].active = YES;
    self.tiltValue = [NSTextField labelWithString:[self tiltTitle:self.tiltDegrees]];
    self.tiltValue.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.tiltValue.alignment = NSTextAlignmentRight;
    [self.tiltValue.widthAnchor constraintEqualToConstant:42].active = YES;
    NSStackView *tiltControl = [NSStackView stackViewWithViews:@[self.tiltSlider, self.tiltValue]];
    tiltControl.spacing = 8;
    self.speedPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.speedPicker.target = self;
    self.speedPicker.action = @selector(selectRotationRate:);
    self.speedPicker.accessibilityLabel = @"旋转速度";
    for (NSMenuItem *item in self.speedMenu.itemArray) {
        [self.speedPicker addItemWithTitle:item.title];
        self.speedPicker.lastItem.representedObject = item.representedObject;
    }
    [self syncMotionControls];
    NSView *motion = [self cardWithRows:@[
        [self rowWithSymbol:@"compass-drawing" title:@"倾斜角度"
                   subtitle:@"0° 使用原始角度" control:tiltControl],
        [self rowWithSymbol:@"gauge" title:@"旋转速度" subtitle:nil control:self.speedPicker],
        [self rowWithSymbol:@"rotate-cw" title:@"旋转"
                   subtitle:nil control:self.rotationSwitch],
    ]];
    return [self paneWithCards:@[[self backgroundPicker],
        [self settingsGroup:@"鹅卵石" containing:stone],
        [self settingsGroup:@"旋转与倾斜" containing:motion]]];
}

// The number is the seed, so the card is literally generated from its own
// serial. Issued once and kept, or it would stop being an identity.
- (NSView *)aboutPane {
    NSImageView *icon = [NSImageView imageViewWithImage:NSApp.applicationIconImage];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [icon.heightAnchor constraintEqualToConstant:76].active = YES;
    [icon.widthAnchor constraintEqualToConstant:76].active = YES;
    NSTextField *name = [NSTextField labelWithString:@"Pebble Wallpaper"];
    name.font = [NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSTextField *version = [NSTextField labelWithString:[NSString stringWithFormat:@"%@（build %@）",
        info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"]]];
    version.font = [NSFont systemFontOfSize:12];
    version.textColor = NSColor.secondaryLabelColor;
    NSStackView *header = [NSStackView stackViewWithViews:@[icon, name, version]];
    header.orientation = NSUserInterfaceLayoutOrientationVertical;
    header.alignment = NSLayoutAttributeCenterX;
    header.spacing = 7;
    header.edgeInsets = NSEdgeInsetsMake(10, 0, 6, 0);

    NSMutableArray *cards = [NSMutableArray arrayWithObject:header];
    NSURL *logURL = [NSBundle.mainBundle URLForResource:@"changelog" withExtension:@"json"];
    NSData *logData = logURL ? [NSData dataWithContentsOfURL:logURL] : nil;
    id entries = logData ? [NSJSONSerialization JSONObjectWithData:logData options:0 error:nil] : nil;
    NSButton *viewAll = [NSButton buttonWithTitle:@"查看全部" target:self action:@selector(openReleases:)];
    viewAll.bordered = NO;
    viewAll.attributedTitle = [[NSAttributedString alloc] initWithString:@"查看全部"
        attributes:@{NSForegroundColorAttributeName:NSColor.linkColor, NSFontAttributeName:[NSFont systemFontOfSize:12]}];
    viewAll.accessibilityLabel = @"查看全部更新日志";
    viewAll.toolTip = @"在浏览器中打开全部历史版本";
    PebbleChangelogView *log = [[PebbleChangelogView alloc] initWithEntries:entries
        currentVersion:info[@"CFBundleShortVersionString"] ?: @"" viewAllButton:viewAll];
    [cards addObject:[self cardWithRows:@[log]]];
#if __has_include(<Sparkle/Sparkle.h>)
    if (self.updaterController) {
        SPUUpdater *updater = self.updaterController.updater;
        NSButton *check = [NSButton buttonWithTitle:@"立即检查"
            target:self.updaterController action:@selector(checkForUpdates:)];
        check.bezelStyle = NSBezelStyleRounded;
        [check setContentHuggingPriority:NSLayoutPriorityRequired
                          forOrientation:NSLayoutConstraintOrientationHorizontal];
        [cards addObject:[self cardWithRows:@[
            [self rowWithSymbol:@"sync" title:@"检查更新"
                       subtitle:nil control:check],
            [self rowWithSymbol:@"search" title:@"自动检查新版本"
                       subtitle:@"每天在后台检查，发现新版时提醒"
                        control:[self switchOn:updater.automaticallyChecksForUpdates
                                        action:@selector(toggleAutomaticChecks:)]],
        ]]];
    }
#endif
    [cards addObject:[self cardWithRows:@[
        [self rowWithSymbol:@"heart" title:@"鸣谢镇长"
                   subtitle:@"这款壁纸基于镇长的原版鹅卵石网页制作"
                    control:[self actionButton:@"打开原版" action:@selector(openOriginal:)]],
    ]]];
    return [self paneWithCards:cards];
}

- (void)openOriginal:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://painted-pebble.vercel.app/"]];
}

- (void)openReleases:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:
        @"https://github.com/DEPYKUNG/pebble-wallpaper-releases/releases"]];
}

- (void)syncSettingsControls {
    [self selectChoice:self.texture inPopUp:self.texturePopUp];
    [self selectChoice:self.palette inPopUp:self.palettePopUp];
    [self selectChoice:self.face inPopUp:self.facePopUp];
    self.rotationSwitch.state = self.paused ? NSControlStateValueOff : NSControlStateValueOn;
}

- (void)settingsWillClose:(NSNotification *)notification {
#if __has_include(<Sparkle/Sparkle.h>)
    // The window still reports itself visible during this notification.
    dispatch_async(dispatch_get_main_queue(), ^{ [self installPendingUpdateIfIdle]; });
#endif
}

#pragma mark - Settings building blocks

- (NSImage *)settingsIcon:(NSString *)name {
    NSURL *url = [NSBundle.mainBundle URLForResource:name withExtension:@"png" subdirectory:@"kubai-settings"];
    NSImage *icon = [[NSImage alloc] initWithContentsOfURL:url];
    icon.size = NSMakeSize(24, 24);
    return icon;
}

- (PebbleRoundedView *)roundedViewFilled:(NSColor *)fill radius:(CGFloat)radius {
    PebbleRoundedView *view = [PebbleRoundedView new];
    view.fill = fill;
    view.radius = radius;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    return view;
}

- (void)pin:(NSView *)view into:(NSView *)container inset:(CGFloat)inset {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:container.topAnchor constant:inset],
        [view.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-inset],
        [view.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:inset],
        [view.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-inset],
    ]];
}

- (NSTextField *)caption:(NSString *)text {
    // Single line on purpose: a wrapping label reports a runaway intrinsic width
    // unless its preferredMaxLayoutWidth is maintained, which wrecks the rows.
    NSTextField *label = [NSTextField labelWithString:text];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.font = [NSFont systemFontOfSize:11];
    label.textColor = NSColor.secondaryLabelColor;
    label.selectable = NO;
    return label;
}

- (NSView *)rowWithSymbol:(NSString *)symbol title:(NSString *)title
                 subtitle:(NSString *)subtitle control:(NSView *)control {
    NSTextField *heading = [NSTextField labelWithString:title];
    heading.font = [NSFont systemFontOfSize:13];
    NSStackView *text = [NSStackView stackViewWithViews:@[heading]];
    text.orientation = NSUserInterfaceLayoutOrientationVertical;
    text.alignment = NSLayoutAttributeLeading;
    text.spacing = 2;
    if (subtitle.length) {
        NSTextField *detail = [self caption:subtitle];
        [text addArrangedSubview:detail];
        [detail setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    [text setContentHuggingPriority:NSLayoutPriorityDefaultLow
                     forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSMutableArray *pieces = [NSMutableArray array];
    if (symbol.length) {
        NSImageView *icon = [NSImageView imageViewWithImage:
            [self settingsIcon:symbol]];
        icon.accessibilityElement = NO;
        [icon.widthAnchor constraintEqualToConstant:24].active = YES;
        [icon.heightAnchor constraintEqualToConstant:24].active = YES;
        [pieces addObject:icon];
    }
    [pieces addObject:text];
    if (control) {
        // A flexible spacer is the dependable way to push the control to the
        // trailing edge; hugging priorities alone leave it next to the subtitle.
        NSView *spacer = [NSView new];
        [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1
                           forOrientation:NSLayoutConstraintOrientationHorizontal];
        [spacer setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 1
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];
        [pieces addObject:spacer];
        [pieces addObject:control];
    }

    NSStackView *row = [NSStackView stackViewWithViews:pieces];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 10;
    row.edgeInsets = NSEdgeInsetsMake(7, 14, 7, 14);
    return row;
}

- (NSView *)cardWithRows:(NSArray<NSView *> *)rows {
    NSStackView *stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 0;
    for (NSView *row in rows) {
        if (stack.arrangedSubviews.count) {
            NSBox *line = [NSBox new];
            line.boxType = NSBoxSeparator;
            [stack addArrangedSubview:line];
            [line.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        }
        [stack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
    // Semantic colour so the card follows light and dark on its own.
    NSColor *cardColor = [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        BOOL dark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]]
                     isEqualToString:NSAppearanceNameDarkAqua];
        return [NSColor colorWithSRGBRed:dark ? .13 : .985
                                   green:dark ? .15 : .985
                                    blue:dark ? .18 : .975 alpha:.90];
    }];
    PebbleRoundedView *card = [self roundedViewFilled:cardColor radius:10];
    card.stroke = NSColor.separatorColor;
    [self pin:stack into:card inset:0];
    return card;
}

- (NSScrollView *)paneWithCards:(NSArray<NSView *> *)cards {
    NSStackView *column = [NSStackView stackViewWithViews:cards];
    column.orientation = NSUserInterfaceLayoutOrientationVertical;
    column.alignment = NSLayoutAttributeLeading;
    column.spacing = 14;
    column.edgeInsets = NSEdgeInsetsMake(22, 22, 22, 22);
    column.translatesAutoresizingMaskIntoConstraints = NO;

    NSScrollView *scroll = [NSScrollView new];
    scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = YES;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    PebbleFlippedView *document = [PebbleFlippedView new];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:column];
    scroll.documentView = document;
    [NSLayoutConstraint activateConstraints:@[
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [document.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [column.topAnchor constraintEqualToAnchor:document.topAnchor],
        [column.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
        [column.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
        [column.bottomAnchor constraintEqualToAnchor:document.bottomAnchor],
    ]];
    for (NSView *card in cards) {
        [card.widthAnchor constraintEqualToAnchor:column.widthAnchor
                                         constant:-(column.edgeInsets.left +
                                                    column.edgeInsets.right)].active = YES;
    }
    return scroll;
}

- (NSPopUpButton *)popUpWithKeys:(const char *const *)keys labels:(const char *const *)labels
                           count:(NSUInteger)count selected:(NSString *)selected
                          action:(SEL)action {
    NSPopUpButton *popUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    popUp.target = self;
    popUp.action = action;
    [popUp addItemWithTitle:@"随机"];
    popUp.lastItem.representedObject = @"";
    for (NSUInteger index = 0; index < count; index++) {
        [popUp addItemWithTitle:@(labels[index])];
        popUp.lastItem.representedObject = @(keys[index]);
    }
    [popUp.widthAnchor constraintGreaterThanOrEqualToConstant:150].active = YES;
    [popUp setContentHuggingPriority:NSLayoutPriorityRequired
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self selectChoice:selected inPopUp:popUp];
    return popUp;
}

- (void)selectChoice:(NSString *)choice inPopUp:(NSPopUpButton *)popUp {
    for (NSMenuItem *item in popUp.itemArray) {
        if ([item.representedObject isEqualToString:choice ?: @""]) [popUp selectItem:item];
    }
}

- (NSButton *)actionButton:(NSString *)title action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    [button setContentHuggingPriority:NSLayoutPriorityRequired
                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    return button;
}

- (NSSwitch *)switchOn:(BOOL)on action:(SEL)action {
    NSSwitch *toggle = [NSSwitch new];
    toggle.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    toggle.target = self;
    toggle.action = action;
    [toggle setContentHuggingPriority:NSLayoutPriorityRequired
                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    return toggle;
}

- (void)editStoneNote:(NSButton *)sender {
    if ((NSUInteger)sender.tag >= self.favorites.count) return;
    NSDictionary *identity = PebbleStoneIdentity(self.favorites[sender.tag]);
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"石头日记";
    alert.informativeText = @"给这颗石头留一句话。留空即可清除备注。";
    [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"取消"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,270,24)];
    field.stringValue = self.favorites[sender.tag][@"note"] ?: @"";
    field.placeholderString = @"例如：搬到新家那天捡到的";
    alert.accessoryView = field;
    alert.window.initialFirstResponder = field;
    [alert beginSheetModalForWindow:self.settings completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        NSUInteger index = [self.favorites indexOfObjectPassingTest:^BOOL(NSDictionary *entry, NSUInteger idx, BOOL *stop) {
            return [PebbleStoneIdentity(entry) isEqual:identity];
        }];
        if (index == NSNotFound) return;
        NSString *note = [field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (note.length > 240) note = [note substringToIndex:[note rangeOfComposedCharacterSequenceAtIndex:240].location];
        NSMutableDictionary *updated = [self.favorites[index] mutableCopy];
        updated[@"note"] = note.length ? note : nil;
        self.favorites[index] = updated;
        if ([PebbleStoneIdentity(self.journalPassStone) isEqual:identity]) self.journalPassStone = updated;
        [self persistFavorites];
    }];
}

- (void)selectFavoriteKind:(NSSegmentedControl *)sender {
    self.showingQuoteFavorites = sender.selectedSegment == 1;
    [self showPaneAtIndex:FavoritesPaneIndex];
}

static NSURL *FavoriteQuoteEpisode(id entry) {
    id link = [entry isKindOfClass:NSDictionary.class] ? entry[@"episode"] : nil;
    NSURL *url = [link isKindOfClass:NSString.class] ? [NSURL URLWithString:link] : nil;
    BOOL valid = [url.scheme isEqualToString:@"https"] && [url.host isEqualToString:@"www.xiaoyuzhoufm.com"] &&
        [url.path rangeOfString:@"^/episode/[a-fA-F0-9]{24}$" options:NSRegularExpressionSearch].location != NSNotFound;
    return valid ? url : nil;
}

- (void)openFavoriteQuote:(NSButton *)sender {
    NSArray *quotes = [NSUserDefaults.standardUserDefaults arrayForKey:@"PetFavoriteQuotes"];
    if ((NSUInteger)sender.tag >= quotes.count) return;
    NSURL *url = FavoriteQuoteEpisode(quotes[sender.tag]);
    if (url) [NSWorkspace.sharedWorkspace openURL:url];
}

- (void)removeFavoriteQuote:(NSButton *)sender {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableArray *quotes = [[defaults arrayForKey:@"PetFavoriteQuotes"] mutableCopy];
    if ((NSUInteger)sender.tag >= quotes.count) return;
    [quotes removeObjectAtIndex:sender.tag];
    [defaults setObject:quotes forKey:@"PetFavoriteQuotes"];
    [self showPaneAtIndex:FavoritesPaneIndex];
}

- (NSView *)favoriteQuoteCollection {
    NSMutableArray *rows = [NSMutableArray array];
    NSArray *quotes = [NSUserDefaults.standardUserDefaults arrayForKey:@"PetFavoriteQuotes"];
    [quotes enumerateObjectsUsingBlock:^(id entry, NSUInteger index, BOOL *stop) {
        if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"text"] isKindOfClass:NSString.class]) return;
        NSButton *remove = [self actionButton:@"移除" action:@selector(removeFavoriteQuote:)];
        remove.tag = index;
        NSMutableArray *buttons = [NSMutableArray array];
        if (FavoriteQuoteEpisode(entry)) {
            NSButton *play = [self actionButton:@"去小宇宙听" action:@selector(openFavoriteQuote:)];
            play.tag = index;
            [buttons addObject:play];
        }
        [buttons addObject:remove];
        [rows addObject:[self rowWithSymbol:nil title:@"金句" subtitle:entry[@"text"]
                                     control:[NSStackView stackViewWithViews:buttons]]];
    }];
    return rows.count ? [self cardWithRows:rows] : [self caption:@"还没有收藏的金句"];
}

- (NSView *)favoritesPane {
    NSSegmentedControl *kind = [NSSegmentedControl segmentedControlWithLabels:@[@"石头", @"金句"]
         trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(selectFavoriteKind:)];
    kind.selectedSegment = self.showingQuoteFavorites ? 1 : 0;
    if (self.showingQuoteFavorites) return [self paneWithCards:@[kind, [self favoriteQuoteCollection]]];
    NSPopUpButton *target = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [target addItemWithTitle:@"所有屏幕"];
    for (NSNumber *display in self.connectedDisplayIdentifiers) {
        [target addItemWithTitle:[self displayTitle:display]]; target.lastItem.representedObject = display;
    }
    if (self.favoriteDisplay && ![self.connectedDisplayIdentifiers containsObject:self.favoriteDisplay]) {
        [target addItemWithTitle:@"已断开的屏幕"]; target.lastItem.representedObject = self.favoriteDisplay; target.lastItem.enabled = NO;
    }
    for (NSMenuItem *item in target.itemArray) if ([item.representedObject isEqual:self.favoriteDisplay]) [target selectItem:item];
    target.target = self; target.action = @selector(selectFavoriteDisplay:); target.accessibilityLabel = @"收藏操作的目标屏幕";
    BOOL available = !self.staticWallpaperMode && PebbleTargetDisplays(self.connectedDisplayIdentifiers, self.favoriteDisplay, NO).count;
    NSButton *saveButton = [self actionButton:@"收藏" action:@selector(saveFavorite:)]; saveButton.enabled = available;
    NSString *hint = self.staticWallpaperMode ? @"恢复动态壁纸后，可收藏和应用石头" : @"收藏所选屏幕；选择所有屏幕时收藏主屏幕";
    NSView *save = [self rowWithSymbol:@"heart" title:@"收藏当前石头" subtitle:hint control:saveButton];
    NSView *scope = [self rowWithSymbol:nil title:@"目标屏幕" subtitle:@"设为当前仅影响这里选择的屏幕" control:target];
    NSMutableArray *rows = [NSMutableArray array];
    [self.favorites enumerateObjectsUsingBlock:^(NSDictionary *stone, NSUInteger index, BOOL *stop) {
        NSButton *restore = [self actionButton:@"设为当前" action:@selector(restoreFavorite:)];
        NSButton *remove = [self actionButton:@"移除" action:@selector(removeFavorite:)];
        restore.tag = remove.tag = index; restore.enabled = available;
        NSButton *pet = [self actionButton:@"用作桌宠" action:@selector(restoreFavoritePet:)];
        pet.tag = index;
        NSButton *pass = [self actionButton:@"看石头证" action:@selector(showJournalPass:)];
        pass.tag = index;
        NSButton *note = [self actionButton:@"备注" action:@selector(editStoneNote:)];
        note.tag = index;
        NSStackView *controls = [NSStackView stackViewWithViews:@[note, pass, restore, pet, remove]];
        NSString *title = [NSString stringWithFormat:@"石头 %lu", (unsigned long)index + 1];
        NSDictionary *sources = @{@"wallpaper":@"桌面壁纸", @"rethrow":@"重新抛", @"pet":@"桌宠", @"skip":@"打水漂"};
        NSString *source = sources[stone[@"collectionSource"] ?: @""];
        NSNumber *timestamp = stone[@"collectedAt"];
        NSString *subtitle = [stone[@"colors"] firstObject];
        if (timestamp && source) {
            NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue];
            NSString *day = [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterMediumStyle
                                                           timeStyle:NSDateFormatterNoStyle];
            subtitle = [NSString stringWithFormat:@"%@ · %@", day, source];
        }
        if ([stone[@"note"] length]) subtitle = [NSString stringWithFormat:@"%@\n%@", subtitle, stone[@"note"]];
        [rows addObject:[self rowWithSymbol:nil title:title subtitle:subtitle control:controls]];
    }];
    NSView *collection = rows.count ? [self cardWithRows:rows] : [self caption:@"还没有收藏的石头"];
    return [self paneWithCards:@[kind, [self cardWithRows:@[scope, save]], collection]];
}

@end
