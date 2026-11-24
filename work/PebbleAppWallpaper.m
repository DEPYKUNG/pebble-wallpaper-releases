#import "PebbleAppInternal.h"

@implementation PebbleApp (Wallpaper)

- (NSURL *)wallpaperSupportDirectory {
    return [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
        inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"Pebble Wallpaper" isDirectory:YES];
}

- (void)syncNativeDesktopBackground:(BOOL)restore {
    [self syncNativeDesktopBackground:restore explicitChange:NO];
}

- (BOOL)syncNativeDesktopBackground:(BOOL)restore explicitChange:(BOOL)explicitChange {
    if (self.testPreviewPath || self.shotPath || self.settingsPreview || self.petPreview) return YES;
    if (self.petOnlyMode && !restore) return YES;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *staticPath = [defaults stringForKey:StaticWallpaperPathKey];
    if (staticPath && [NSFileManager.defaultManager fileExistsAtPath:staticPath]) return YES;
    NSURL *directory = [self.wallpaperSupportDirectory URLByAppendingPathComponent:@"Desktop Backgrounds" isDirectory:YES];
    NSURL *staticDirectory = [self.wallpaperSupportDirectory URLByAppendingPathComponent:@"Static Wallpapers" isDirectory:YES];
    NSMutableArray *ownedURLs = [NSMutableArray array];
    NSURL *background = nil;
    for (NSString *preset in @[@"nord0", @"nord3"]) {
        NSString *name = [@"desktop-base-" stringByAppendingString:preset];
        NSURL *bundled = [NSBundle.mainBundle URLForResource:name withExtension:@"png"];
        NSURL *stable = [directory URLByAppendingPathComponent:[name stringByAppendingString:@".png"]];
        if (bundled) [ownedURLs addObject:bundled];
        [ownedURLs addObject:stable];
        if (!restore && [self.backgroundPreset isEqual:preset]) {
            NSError *error = nil;
            if (!bundled) { NSLog(@"Bundled background resource is missing."); return NO; }
            NSData *image = [NSData dataWithContentsOfURL:bundled options:0 error:&error];
            if (!image || ![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error] ||
                (![image isEqual:[NSData dataWithContentsOfURL:stable]] && ![image writeToURL:stable options:NSDataWritingAtomic error:&error])) {
                NSLog(@"Could not prepare stable native wallpaper: %@", error); return NO;
            }
            background = stable;
        }
    }
    NSMutableDictionary *originals = [[defaults dictionaryForKey:OriginalDesktopImagesKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *managedURLs = [[defaults dictionaryForKey:@"ManagedDesktopImageURLs"] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *blocked = [[defaults dictionaryForKey:@"NativeWallpaperUserOverrides"] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSWorkspace *workspace = NSWorkspace.sharedWorkspace;
    BOOL success = YES;
    for (NSScreen *screen in NSScreen.screens) {
        NSNumber *display = screen.deviceDescription[@"NSScreenNumber"];
        if (!display) continue;
        NSString *key = display.stringValue;
        NSURL *current = [workspace desktopImageURLForScreen:screen];
        id record = originals[key];
        NSDictionary *original = [record isKindOfClass:NSDictionary.class] ? record : nil;
        NSString *savedURL = [original[@"url"] isKindOfClass:NSString.class] ? original[@"url"] : nil;
        NSURL *previous = savedURL ? [NSURL URLWithString:savedURL] : nil;
        BOOL managed = PebbleWallpaperURLIsManaged(current, ownedURLs, managedURLs[key], staticDirectory);
        PebbleWallpaperAction action = PebbleWallpaperPlan(current, background, managed, previous.isFileURL,
            [blocked[key] isKindOfClass:NSNumber.class] && [blocked[key] boolValue], explicitChange);
        if (action == PebbleWallpaperRespectUser) {
            // A wallpaper chosen outside Pebble wins until the user picks a background here again.
            [originals removeObjectForKey:key]; [managedURLs removeObjectForKey:key]; blocked[key] = @YES;
            continue;
        }
        if (explicitChange) [blocked removeObjectForKey:key];
        if (action == PebbleWallpaperNothing) continue;
        if (action == PebbleWallpaperCaptureAndInstall) {
            NSDictionary *options = [workspace desktopImageOptionsForScreen:screen] ?: @{};
            NSData *encoded = [NSKeyedArchiver archivedDataWithRootObject:options requiringSecureCoding:YES error:nil];
            originals[key] = @{@"url":current.absoluteString, @"options":encoded ?: NSData.data};
            // Save before handing control to the system so an interrupted install can recover.
            [defaults setObject:originals forKey:OriginalDesktopImagesKey];
        }
        NSURL *target = action == PebbleWallpaperRestore ? previous : background;
        NSDictionary *options = @{};
        if (action == PebbleWallpaperRestore) {
            NSData *data = [original[@"options"] isKindOfClass:NSData.class] ? original[@"options"] : nil;
            if (data.length) {
                NSSet *classes = [NSSet setWithArray:@[NSDictionary.class, NSString.class, NSNumber.class, NSColor.class]];
                @try { options = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:nil] ?: @{}; }
                @catch (NSException *exception) { NSLog(@"Ignoring invalid saved wallpaper options: %@", exception.name); }
            }
        }
        NSError *error = nil;
        if (!target || ![NSFileManager.defaultManager fileExistsAtPath:target.path] ||
            ![workspace setDesktopImageURL:target forScreen:screen options:options error:&error]) {
            if (action == PebbleWallpaperCaptureAndInstall) {
                if (record) originals[key] = record; else [originals removeObjectForKey:key];
            }
            success = NO; NSLog(@"Native wallpaper change deferred for display %@: %@", key, error); continue;
        }
        if (action == PebbleWallpaperRestore) {
            [originals removeObjectForKey:key]; [managedURLs removeObjectForKey:key]; [blocked removeObjectForKey:key];
        } else managedURLs[key] = target.absoluteString;
    }
    // Disconnected displays remain in these dictionaries until they can be restored.
    [defaults setObject:originals forKey:OriginalDesktopImagesKey];
    [defaults setObject:managedURLs forKey:@"ManagedDesktopImageURLs"];
    [defaults setObject:blocked forKey:@"NativeWallpaperUserOverrides"];
    return success;
}

- (NSArray<NSString *> *)stoneTextures {
    NSMutableArray *textures = [NSMutableArray array];
    for (NSUInteger index = 0; index < PebbleTextureCount; index++) [textures addObject:@(PebbleTextureKeys[index])];
    return textures;
}

- (NSString *)jsonForPebble:(NSDictionary *)object {
    if (![NSJSONSerialization isValidJSONObject:object]) return @"null";
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"null";
}

- (NSData *)wallpaperPNGFromBase64:(id)value size:(WallpaperExportSize)size {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSData *png = [[NSData alloc] initWithBase64EncodedString:value options:0];
    NSBitmapImageRep *image = png ? [NSBitmapImageRep imageRepWithData:png] : nil;
    return image.pixelsWide == size.width && image.pixelsHigh == size.height ? png : nil;
}

- (void)showWallpaperError:(NSString *)detail {
    if (self.testPreviewPath || self.shotPath) {
        self.verificationCommandErrors++; NSLog(@"Operation feedback: %@", detail); return;
    }
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    if (self.showingOperationError || now - self.lastOperationError < 2) return;
    self.showingOperationError = YES; self.lastOperationError = now;
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [NSAlert new]; alert.messageText = @"操作未完成"; alert.informativeText = detail;
    [alert runModal]; self.showingOperationError = NO;
}

- (NSData *)resizeStaticWallpaperPNG:(NSData *)png size:(WallpaperExportSize)size {
    NSBitmapImageRep *source = png ? [NSBitmapImageRep imageRepWithData:png] : nil;
    if (!source || source.pixelsWide != 3840 || source.pixelsHigh != 2160) return nil;
    if (size.width == 3840 && size.height == 2160) return png;
    NSBitmapImageRep *output = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:size.width pixelsHigh:size.height bitsPerSample:8 samplesPerPixel:4
        hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    if (!output) return nil;
    NSImage *image = [[NSImage alloc] initWithData:png]; image.size = NSMakeSize(3840, 2160);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:output];
    NSGraphicsContext.currentContext.imageInterpolation = NSImageInterpolationHigh;
    [[source colorAtX:0 y:0] setFill]; NSRectFill(NSMakeRect(0, 0, size.width, size.height));
    CGFloat square = MIN(size.width, size.height);
    CGFloat centerY = size.height * (size.height > size.width ? .44 : .5);
    [image drawInRect:NSMakeRect((size.width-square)/2, centerY-square/2, square, square)
        fromRect:NSMakeRect(840, 0, 2160, 2160) operation:NSCompositingOperationSourceOver fraction:1];
    [NSGraphicsContext restoreGraphicsState];
    return [output representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

- (void)withWallpaperPNGForSize:(WallpaperExportSize)size completion:(void (^)(NSData *))completion {
    [self withWallpaperPNGForSize:size display:self.connectedDisplayIdentifiers.firstObject completion:completion];
}

- (void)withWallpaperPNGForSize:(WallpaperExportSize)size display:(NSNumber *)display completion:(void (^)(NSData *))completion {
    WKWebView *web = display ? (WKWebView *)self.desktopWindows[display].contentView : nil;
    if (!web) { [self showWallpaperError:@"所选屏幕已断开，请重新选择屏幕。"]; return; }
    NSString *path = [NSUserDefaults.standardUserDefaults stringForKey:StaticWallpaperPathKey];
    if (self.staticWallpaperMode && path) {
        NSData *png = [self resizeStaticWallpaperPNG:[NSData dataWithContentsOfFile:path] size:size];
        if (png) completion(png);
        else [self showWallpaperError:@"保存的静态壁纸无法读取，请恢复动态壁纸后重新设置。"];
        return;
    }
    NSString *script = [NSString stringWithFormat:@"window.pebbleExport(%lu,%lu)",
                        (unsigned long)size.width, (unsigned long)size.height];
    [web evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        NSData *png = [self wallpaperPNGFromBase64:result size:size];
        if (png) completion(png);
        else [self showWallpaperError:error.localizedDescription ?: @"鹅卵石还在加载，请稍后再试。"];
    }];
}

- (void)exportWallpaper:(NSMenuItem *)sender {
    if ((NSUInteger)sender.tag >= WallpaperSizeCount) return;
    WallpaperExportSize size = WallpaperSizes[sender.tag];
    [self withWallpaperPNGForSize:size display:sender.representedObject completion:^(NSData *png) {
        [NSApp activateIgnoringOtherApps:YES];
        NSSavePanel *panel = [NSSavePanel savePanel];
        panel.allowedContentTypes = @[UTTypePNG];
        panel.nameFieldStringValue = [NSString stringWithFormat:@"鹅卵石壁纸-%@.png", size.name];
        if ([panel runModal] != NSModalResponseOK) return;
        NSError *error = nil;
        if (![png writeToURL:panel.URL options:NSDataWritingAtomic error:&error]) {
            [self showWallpaperError:error.localizedDescription];
        }
    }];
}

- (void)setStaticWallpaper:(id)sender {
    if (self.petOnlyMode) {
        [self showWallpaperError:@"请先在「显示模式」中切换到动态壁纸。"];
        return;
    }
    [self withWallpaperPNGForSize:WallpaperSizes[0] completion:^(NSData *png) {
        if (self.petOnlyMode) return;
        NSFileManager *files = NSFileManager.defaultManager;
        NSURL *directory = [[files URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject
                            URLByAppendingPathComponent:@"Pebble Wallpaper/Static Wallpapers" isDirectory:YES];
        NSURL *url = [directory URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".png"]];
        NSError *error = nil;
        if (![files createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error] ||
            ![png writeToURL:url options:NSDataWritingAtomic error:&error]) {
            [self showWallpaperError:error.localizedDescription];
            return;
        }

        NSWorkspace *workspace = NSWorkspace.sharedWorkspace;
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSDictionary *savedOriginals = [defaults dictionaryForKey:OriginalDesktopImagesKey] ?: @{};
        NSMutableDictionary *originals = [savedOriginals mutableCopy];
        NSMutableArray<void (^)(void)> *undo = [NSMutableArray array];
        for (NSScreen *screen in NSScreen.screens) {
            NSURL *previous = [workspace desktopImageURLForScreen:screen];
            NSDictionary *options = [workspace desktopImageOptionsForScreen:screen] ?: @{};
            NSString *key = [screen.deviceDescription[@"NSScreenNumber"] stringValue];
            NSMutableArray *owned = [NSMutableArray array];
            for (NSString *preset in @[@"nord0", @"nord3"]) {
                NSString *name = [@"desktop-base-" stringByAppendingString:preset];
                NSURL *bundled = [NSBundle.mainBundle URLForResource:name withExtension:@"png"];
                if (bundled) [owned addObject:bundled];
                [owned addObject:[[self.wallpaperSupportDirectory URLByAppendingPathComponent:@"Desktop Backgrounds"]
                    URLByAppendingPathComponent:[name stringByAppendingString:@".png"]]];
            }
            NSDictionary *managed = [defaults dictionaryForKey:@"ManagedDesktopImageURLs"] ?: @{};
            BOOL wasManaged = PebbleWallpaperURLIsManaged(previous, owned, managed[key], directory);
            if (previous && key && !wasManaged) {
                NSData *encoded = [NSKeyedArchiver archivedDataWithRootObject:options requiringSecureCoding:YES error:nil];
                originals[key] = @{@"url":previous.absoluteString, @"options":encoded ?: NSData.data};
                [defaults setObject:originals forKey:OriginalDesktopImagesKey];
            }
            if (![workspace setDesktopImageURL:url forScreen:screen
                                       options:@{NSWorkspaceDesktopImageScalingKey:@(NSImageScaleProportionallyUpOrDown),
                                                 NSWorkspaceDesktopImageAllowClippingKey:@YES} error:&error]) {
                for (void (^restore)(void) in undo.reverseObjectEnumerator) restore();
                [defaults setObject:savedOriginals forKey:OriginalDesktopImagesKey];
                [self showWallpaperError:error.localizedDescription ?: @"macOS 无法设置这张壁纸。"];
                return;
            }
            if (previous) [undo addObject:^{ [workspace setDesktopImageURL:previous forScreen:screen options:options error:nil]; }];
        }
        [NSUserDefaults.standardUserDefaults setObject:url.path forKey:StaticWallpaperPathKey];
        [self refreshDisplays:nil];
    }];
}

- (void)enablePetOnlyMode:(id)sender {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    self.petOnlyMode = YES;
    [defaults setBool:YES forKey:@"PetOnlyMode"];
    [defaults removeObjectForKey:StaticWallpaperPathKey];
    [self summonPet:nil];
    BOOL restored = [self syncNativeDesktopBackground:YES explicitChange:NO];
    [self refreshDisplays:nil];
    if (!restored) {
        [self showWallpaperError:@"部分屏幕的原壁纸无法恢复，可在 macOS 系统设置中重新选择。"];
    }
}

- (void)resumeDynamicWallpaper:(id)sender {
    self.petOnlyMode = NO;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"PetOnlyMode"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:StaticWallpaperPathKey];
    [self refreshDisplays:nil];
}

- (NSArray<NSNumber *> *)connectedDisplayIdentifiers {
    NSMutableArray *result = [NSMutableArray array];
    for (NSScreen *screen in NSScreen.screens) {
        NSNumber *display = screen.deviceDescription[@"NSScreenNumber"];
        if (display && self.desktopWindows[display]) [result addObject:display];
    }
    return result;
}

- (NSString *)displayTitle:(NSNumber *)display {
    for (NSScreen *screen in NSScreen.screens) {
        if ([screen.deviceDescription[@"NSScreenNumber"] isEqual:display]) return [NSString stringWithFormat:@"%@ · %@",
            [display isEqual:self.connectedDisplayIdentifiers.firstObject] ? @"主屏幕" : @"屏幕", screen.localizedName];
    }
    return @"已断开的屏幕";
}

- (void)previousPebble:(NSMenuItem *)sender {
    for (NSNumber *display in PebbleTargetDisplays(self.connectedDisplayIdentifiers, sender.representedObject, YES)) {
        NSWindow *window = self.desktopWindows[display];
        if (window.isVisible) [self performWallpaperScript:@"window.pebblePrevious()" inWeb:(WKWebView *)window.contentView reportErrors:YES completion:nil];
    }
}

- (void)selectFavoriteDisplay:(NSPopUpButton *)sender {
    self.favoriteDisplay = sender.selectedItem.representedObject;
    [self showPaneAtIndex:FavoritesPaneIndex];
}

- (void)persistFavorites {
    [NSUserDefaults.standardUserDefaults setObject:self.favorites forKey:PebbleFavoritesKey];
    if (self.settings && self.selectedSettingsPane == FavoritesPaneIndex) {
        [self showPaneAtIndex:FavoritesPaneIndex];
    }
}

- (void)saveFavorite:(id)sender {
    if (self.staticWallpaperMode) return;
    NSNumber *display = PebbleTargetDisplays(self.connectedDisplayIdentifiers, self.favoriteDisplay, NO).firstObject;
    WKWebView *web = display ? (WKWebView *)self.desktopWindows[display].contentView : nil;
    if (!web) { [self showWallpaperError:@"所选屏幕已断开，请重新选择屏幕。"]; return; }
    [web evaluateJavaScript:@"({...window.pebbleSnapshot(),rethrow:window.pebbleSnapshot().seed===window.pebbleLastThrow})" completionHandler:^(id value, NSError *error) {
        NSDictionary *stone = error ? nil : PebbleNormalizeStone(value, self.stoneTextures);
        if (!stone) { [self showWallpaperError:@"石头尚未加载完成，请稍后再收藏。"]; return; }
        [self storeFavoriteStone:stone source:[value[@"rethrow"] boolValue] ? @"rethrow" : @"wallpaper"];
    }];
}

- (void)storeFavoriteStone:(NSDictionary *)stone source:(NSString *)source {
    NSMutableDictionary *entry = [stone mutableCopy];
    entry[@"collectedAt"] = @(NSDate.date.timeIntervalSince1970);
    entry[@"collectionSource"] = source;
    for (NSUInteger index = 0; index < self.favorites.count; index++) {
        if ([PebbleStoneIdentity(self.favorites[index]) isEqual:PebbleStoneIdentity(stone)]) {
            NSDictionary *previous = self.favorites[index];
            entry[@"collectedAt"] = previous[@"collectedAt"];
            entry[@"collectionSource"] = previous[@"collectionSource"];
            self.favorites[index] = entry;
            [self persistFavorites];
            return;
        }
    }
    [self.favorites addObject:entry];
    [self persistFavorites];
}

- (void)restoreFavorite:(NSButton *)sender {
    if ((NSUInteger)sender.tag >= self.favorites.count) return;
    if (self.staticWallpaperMode) return;
    NSArray *targets = PebbleTargetDisplays(self.connectedDisplayIdentifiers, self.favoriteDisplay, YES);
    if (!targets.count) { [self showWallpaperError:@"所选屏幕已断开，请重新选择屏幕。"]; return; }
    NSString *script = [NSString stringWithFormat:@"window.pebbleRestore(%@)", [self jsonForPebble:self.favorites[sender.tag]]];
    for (NSNumber *display in targets) [self performWallpaperScript:script inWeb:(WKWebView *)self.desktopWindows[display].contentView reportErrors:YES completion:nil];

}

- (void)removeFavorite:(NSButton *)sender {
    if ((NSUInteger)sender.tag >= self.favorites.count) return;
    [self.favorites removeObjectAtIndex:sender.tag];
    [self persistFavorites];
}

@end
