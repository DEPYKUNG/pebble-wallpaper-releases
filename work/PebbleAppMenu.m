#import "PebbleAppInternal.h"

@implementation PebbleApp (Menu)

- (NSMenuItem *)addItem:(NSString *)title action:(SEL)action toMenu:(NSMenu *)menu {
    NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    return item;
}

// Anything outside the generated tables names something the renderer cannot
// draw, and an unknown key would quietly fall back to a plain random stone.
- (NSString *)known:(NSString *)candidate in:(const char *const *)keys count:(NSUInteger)count {
    for (NSUInteger index = 0; index < count; index++) {
        if ([candidate isEqualToString:@(keys[index])]) return candidate;
    }
    return nil;
}

- (NSMenu *)addChoicesTitled:(NSString *)title keys:(const char *const *)keys
                      labels:(const char *const *)labels count:(NSUInteger)count
                      action:(SEL)action toMenu:(NSMenu *)menu {
    NSMenu *choices = [[NSMenu alloc] initWithTitle:title];
    [self addItem:@"随机" action:action toMenu:choices].representedObject = @"";
    [choices addItem:NSMenuItem.separatorItem];
    for (NSUInteger index = 0; index < count; index++) {
        [self addItem:@(labels[index]) action:action toMenu:choices]
            .representedObject = @(keys[index]);
    }
    [menu addItemWithTitle:title action:nil keyEquivalent:@""].submenu = choices;
    return choices;
}

- (void)addChoiceMenusTo:(NSMenu *)menu {
    self.textureMenu = [self addChoicesTitled:@"鹅卵石材质" keys:PebbleTextureKeys
                                       labels:PebbleTextureLabels count:PebbleTextureCount
                                       action:@selector(selectTexture:) toMenu:menu];
    self.paletteMenu = [self addChoicesTitled:@"鹅卵石颜色" keys:PebbleColorKeys
                                       labels:PebbleColorLabels count:PebbleColorCount
                                       action:@selector(selectPalette:) toMenu:menu];
    self.faceMenu = [self addChoicesTitled:@"鹅卵石脸孔" keys:PebbleFaceKeys
                                    labels:PebbleFaceLabels count:PebbleFaceCount
                                    action:@selector(selectFace:) toMenu:menu];
    [self mark:self.texture inMenu:self.textureMenu];
    [self mark:self.palette inMenu:self.paletteMenu];
    [self mark:self.face inMenu:self.faceMenu];
}

- (void)mark:(NSString *)selected inMenu:(NSMenu *)menu {
    for (NSMenuItem *item in menu.itemArray) {
        if (!item.representedObject) continue;
        item.state = [item.representedObject isEqualToString:selected ?: @""] ?
            NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (NSString *)tiltTitle:(NSInteger)degrees {
    return degrees == 0 ? @"0°" : [NSString stringWithFormat:@"%+ld°", (long)degrees];
}

- (NSString *)rateTitle:(double)rate {
    return [NSString stringWithFormat:@"%g×", rate];
}

- (void)addMotionMenusTo:(NSMenu *)menu {
    self.tiltMenu = [[NSMenu alloc] initWithTitle:@"倾斜角度"];
    for (NSUInteger i = 0; i < sizeof(TiltPresets) / sizeof(TiltPresets[0]); i++) {
        NSInteger degrees = TiltPresets[i];
        [self addItem:[self tiltTitle:degrees] action:@selector(selectTilt:) toMenu:self.tiltMenu]
            .representedObject = @(degrees);
    }
    [self.tiltMenu addItem:NSMenuItem.separatorItem];
    [self addItem:@"自定…" action:@selector(showTiltSettings:) toMenu:self.tiltMenu];
    [menu addItemWithTitle:@"倾斜角度" action:nil keyEquivalent:@""].submenu = self.tiltMenu;

    self.speedMenu = [[NSMenu alloc] initWithTitle:@"旋转速度"];
    for (NSUInteger i = 0; i < sizeof(RotationRates) / sizeof(RotationRates[0]); i++) {
        double rate = RotationRates[i];
        [self addItem:[self rateTitle:rate] action:@selector(selectRotationRate:) toMenu:self.speedMenu]
            .representedObject = @(rate);
    }
    [menu addItemWithTitle:@"旋转速度" action:nil keyEquivalent:@""].submenu = self.speedMenu;
    [self syncMotionControls];
}

- (void)showTiltSettings:(id)sender {
    [self showSettings:nil];
    [self showPaneAtIndex:0];
    [self.settings makeFirstResponder:self.tiltSlider];
}

- (void)syncMotionControls {
    NSString *tilt = [self tiltTitle:self.tiltDegrees];
    self.tiltSlider.integerValue = self.tiltDegrees;
    self.tiltValue.stringValue = tilt;
    [self.speedPicker selectItemWithTitle:[self rateTitle:self.rotationRate]];
    for (NSMenuItem *item in self.tiltMenu.supermenu.itemArray) {
        if (item.submenu == self.tiltMenu) item.title = [@"倾斜角度  " stringByAppendingString:tilt];
    }
    for (NSMenuItem *item in self.tiltMenu.itemArray) {
        if (item.representedObject) item.state = [item.representedObject isEqual:@(self.tiltDegrees)];
    }
    for (NSMenuItem *item in self.speedMenu.itemArray) {
        item.state = [item.representedObject isEqual:@(self.rotationRate)];
    }
}

- (NSString *)motionConfigScript {
    return [NSString stringWithFormat:@"window.pebbleConfig = window.pebbleConfig || {};"
            "window.pebbleConfig.tiltDegrees = %ld; window.pebbleConfig.rotationRate = %.1f;",
            (long)self.tiltDegrees, self.rotationRate];
}

- (void)updateMotionRenderers:(BOOL)restartTimer {
    [self syncRendererStartupScripts];
    NSString *update = restartTimer
        ? @"document.dispatchEvent(new Event('visibilitychange'));" : @"window.pebbleRedraw?.();";
    NSString *script = [self.motionConfigScript stringByAppendingString:update];
    [self forEachRenderer:^(WKWebView *web) {
        [self performWallpaperScript:script inWeb:web reportErrors:YES completion:nil];
    }];
}

- (void)selectTilt:(id)sender {
    NSInteger degrees = [sender isKindOfClass:NSSlider.class]
        ? [sender integerValue] : [[sender representedObject] integerValue];
    self.tiltDegrees = MAX(-TiltLimit, MIN(TiltLimit, degrees));
    [NSUserDefaults.standardUserDefaults setInteger:self.tiltDegrees forKey:TiltPreference];
    [self syncMotionControls];
    [self updateMotionRenderers:NO];
}

- (void)selectRotationRate:(id)sender {
    NSMenuItem *item = [sender isKindOfClass:NSPopUpButton.class] ? [sender selectedItem] : sender;
    self.rotationRate = [item.representedObject doubleValue];
    [NSUserDefaults.standardUserDefaults setDouble:self.rotationRate forKey:SpeedPreference];
    [self syncMotionControls];
    [self updateMotionRenderers:YES];
}

- (NSString *)backgroundConfigScript {
    NSUInteger index = 0;
    while (index + 1 < BackgroundCount && ![self.backgroundPreset isEqualToString:@(BackgroundKeys[index])]) index++;
    return [NSString stringWithFormat:
        @"document.documentElement.dataset.pebbleBackground = '%@';"
         "document.documentElement.style.setProperty('--wallpaper-background', '#%06lX');",
        self.backgroundPreset, (unsigned long)BackgroundColors[index]];
}

- (NSString *)rendererConfigScript {
    // Both keys come from the generated tables, so they are plain identifiers.
    NSString *texture = self.texture ? [NSString stringWithFormat:@"'%@'", self.texture] : @"null";
    NSString *palette = self.palette ? [NSString stringWithFormat:@"'%@'", self.palette] : @"null";
    return [NSString stringWithFormat:@"window.pebbleConfig = window.pebbleConfig || {};"
            "window.pebbleConfig.texture = %@; window.pebbleConfig.palette = %@;"
            "window.pebbleConfig.faces = %@;"
            "window.pebbleStaticPaused = %@;window.pebblePaused = %@;%@%@%@",
            texture, palette,
            self.face ? [NSString stringWithFormat:@"'%@'", self.face] : @"null",
            self.staticWallpaperMode ? @"true" : @"false", self.paused ? @"true" : @"false",
            self.smartPauseScript, self.backgroundConfigScript, self.motionConfigScript];
}

- (void)storeChoice:(NSString *)choice forKey:(NSString *)key {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (choice) {
        [defaults setObject:choice forKey:key];
    } else {
        [defaults removeObjectForKey:key];
    }
    [self syncSettingsControls];
    [self syncRendererStartupScripts];
    [self forEachRenderer:^(WKWebView *web) {
        [self performWallpaperScript:self.rendererConfigScript inWeb:web reportErrors:YES completion:nil];
    }];
    // The stone already on screen keeps whatever it was raised with.
    [self changePebble:nil];
}

- (void)selectFace:(id)sender {
    self.face = [self known:[self choiceFrom:sender] in:PebbleFaceKeys count:PebbleFaceCount];
    [self mark:self.face inMenu:self.faceMenu];
    [self storeChoice:self.face forKey:FacePreference];
}

- (NSString *)choiceFrom:(id)sender {
    NSMenuItem *item = [sender isKindOfClass:NSPopUpButton.class] ?
        ((NSPopUpButton *)sender).selectedItem : sender;
    return item.representedObject;
}

- (void)selectTexture:(id)sender {
    self.texture = [self known:[self choiceFrom:sender]
                            in:PebbleTextureKeys count:PebbleTextureCount];
    [self mark:self.texture inMenu:self.textureMenu];
    [self storeChoice:self.texture forKey:TexturePreference];
}

- (void)selectPalette:(id)sender {
    self.palette = [self known:[self choiceFrom:sender]
                            in:PebbleColorKeys count:PebbleColorCount];
    [self mark:self.palette inMenu:self.paletteMenu];
    [self storeChoice:self.palette forKey:PalettePreference];
}

@end
