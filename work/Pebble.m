#import "PebbleAppInternal.h"

static NSMenu *AddSubmenu(NSMenu *menu, NSString *title) {
    NSMenuItem *item = [menu addItemWithTitle:title action:nil keyEquivalent:@""];
    item.submenu = [[NSMenu alloc] initWithTitle:title];
    return item.submenu;
}

@implementation PebbleApp

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    self.paused = [defaults boolForKey:PausedPreference];
    id oldHistory = [defaults objectForKey:PebbleHistoryKey], oldFavorites = [defaults objectForKey:PebbleFavoritesKey];
    self.pebbleHistory = [PebbleNormalizeHistories(oldHistory, self.stoneTextures) mutableCopy];
    self.favorites = [PebbleNormalizeFavorites(oldFavorites, self.stoneTextures) mutableCopy];
    if (!self.testPreviewPath && !self.shotPath && !self.settingsPreview &&
        ((oldHistory && ![oldHistory isEqual:self.pebbleHistory]) || (oldFavorites && ![oldFavorites isEqual:self.favorites])) &&
        ![defaults objectForKey:@"PebbleDataBackupBeforeSchema1"]) {
        [defaults setObject:@{@"history":oldHistory ?: @{}, @"favorites":oldFavorites ?: @[]} forKey:@"PebbleDataBackupBeforeSchema1"];
    }
    self.tiltDegrees = MAX(-TiltLimit, MIN(TiltLimit, [defaults integerForKey:TiltPreference]));
    self.rotationRate = 1;
    double savedRate = [defaults doubleForKey:SpeedPreference];
    for (NSUInteger i = 0; i < sizeof(RotationRates) / sizeof(RotationRates[0]); i++) {
        if (savedRate == RotationRates[i]) self.rotationRate = savedRate;
    }
    self.face = [self known:[NSUserDefaults.standardUserDefaults stringForKey:FacePreference]
                         in:PebbleFaceKeys count:PebbleFaceCount];
    self.texture = [self known:[NSUserDefaults.standardUserDefaults stringForKey:TexturePreference]
                            in:PebbleTextureKeys count:PebbleTextureCount];
    self.palette = [self known:[NSUserDefaults.standardUserDefaults stringForKey:PalettePreference]
                            in:PebbleColorKeys count:PebbleColorCount];
    self.backgroundPreset = [self known:[NSUserDefaults.standardUserDefaults stringForKey:BackgroundPreference]
                                       in:BackgroundKeys count:BackgroundCount] ?: @"paper";
    self.desktopWindows = [NSMutableDictionary dictionary];
    self.desktopControls = [NSMutableDictionary dictionary];
    self.rendererRecovery = [NSMapTable weakToStrongObjectsMapTable];
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = PebbleMenuBarIcon();
    self.statusItem.button.toolTip = WallpaperTitle;

    NSMenu *menu = [[NSMenu alloc] initWithTitle:WallpaperTitle];
    self.petOnlyMode = [NSUserDefaults.standardUserDefaults boolForKey:@"PetOnlyMode"];
    self.rethrowItem = [self addItem:@"重新抛" action:@selector(changePebble:) toMenu:menu];
    self.previousItem = [self addItem:@"上一颗" action:@selector(previousPebble:) toMenu:menu];
    self.rethrowMenu = [[NSMenu alloc] initWithTitle:self.rethrowItem.title];
    self.previousMenu = [[NSMenu alloc] initWithTitle:self.previousItem.title];
    [menu addItem:NSMenuItem.separatorItem];

    NSMenu *mode = AddSubmenu(menu, @"显示模式");
    self.dynamicModeItem = [self addItem:@"动态壁纸" action:@selector(resumeDynamicWallpaper:) toMenu:mode];
    self.staticModeItem = [self addItem:@"静态壁纸（主屏幕 → 所有屏幕）" action:@selector(setStaticWallpaper:) toMenu:mode];
    self.petOnlyModeItem = [self addItem:@"仅桌宠" action:@selector(enablePetOnlyMode:) toMenu:mode];

    NSMenu *wallpaper = AddSubmenu(menu, @"壁纸选项");
    [self addChoiceMenusTo:wallpaper];
    [self addMotionMenusTo:wallpaper];
    self.pauseItem = [self addItem:@"旋转开关" action:@selector(togglePause:) toMenu:wallpaper];
    self.pauseItem.state = !self.paused;
    NSMenuItem *smart = [self addItem:@"智能暂停" action:@selector(toggleSmartPause:) toMenu:wallpaper];
    smart.state = ![NSUserDefaults.standardUserDefaults boolForKey:SmartPauseDisabledKey];
    self.exportMenu = AddSubmenu(wallpaper, @"导出静态壁纸");
    [self configurePetMenu:menu];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *settingsItem = [self addItem:@"设置…" action:@selector(showSettings:) toMenu:menu];
    settingsItem.keyEquivalent = @",";
#if __has_include(<Sparkle/Sparkle.h>)
    if (!self.testPreviewPath && !self.shotPath && !self.settingsPreview && !self.petPreview) {
        self.updaterController = [[SPUStandardUpdaterController alloc]
            initWithStartingUpdater:YES updaterDelegate:self userDriverDelegate:nil];
        NSMenuItem *updateItem = [menu addItemWithTitle:@"检查更新…"
            action:@selector(checkForUpdates:) keyEquivalent:@""];
        updateItem.target = self.updaterController;
#ifdef PEBBLE_UPDATE_TEST
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--check-for-updates"]) {
            self.updaterController.updater.automaticallyDownloadsUpdates = YES;
            [self.updaterController.updater checkForUpdatesInBackground];
        }
#endif
    }
#endif
    [self addItem:@"退出鹅卵石" action:@selector(quit:) toMenu:menu];
    self.statusItem.menu = menu;
    // Renders a settings pane straight to PNG. The window's layout cannot be
    // checked any other way, and screen capture needs permissions a build box
    // will not have. Same kind of affordance as --verify.
    if (self.settingsPreview) {
        [self showSettings:nil];
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--preview-pet-settings"]) [self showPaneAtIndex:PetPaneIndex];
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--preview-about"]) [self showPaneAtIndex:AboutPaneIndex];
        return;
    }
    if (self.shotPath) {
        [self showSettings:nil];
        [self showPaneAtIndex:self.shotSection];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2200 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            if (self.shotSection == PassPaneIndex) {
                [self capturePassForVerification];
                return;
            }
            NSView *view = self.settings.contentView;
            NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
            [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
            [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                writeToFile:self.shotPath atomically:YES];
            [NSApp terminate:nil];
        });
        return;
    }
    if (!self.testPreviewPath) [self observeSmartPause];
    [self refreshDisplays:nil];
    [self updatePetPresentation];
    if(self.petPreview && [NSProcessInfo.processInfo.arguments containsObject:@"--preview-pet-settings"]) [self showPetSettings:nil];
    if (!self.testPreviewPath) [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshDisplays:)
                 name:NSApplicationDidChangeScreenParametersNotification object:NSApp];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.pet invalidate];
    [self syncNativeDesktopBackground:YES];
}

- (void)quit:(id)sender {
    [NSApp terminate:sender];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        PebbleApp *delegate = [PebbleApp new];
        if (argc == 3 && strcmp(argv[1], "--verify") == 0) {
            delegate.testPreviewPath = @(argv[2]);
        }
        if (argc >= 4 && strcmp(argv[1], "--shoot") == 0) {
            delegate.shotPath = @(argv[2]);
            delegate.shotSection = atoi(argv[3]);
            if (argc == 5) delegate.shotPassNumber = atoi(argv[4]);
        }
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--preview-pet"]) delegate.petPreview = YES;
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--preview-settings"]) delegate.settingsPreview = YES;
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
