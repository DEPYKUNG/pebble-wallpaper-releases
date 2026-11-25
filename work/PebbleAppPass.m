#import "PebbleAppInternal.h"

@implementation PebbleApp (Pass)

- (NSInteger)passNumber {
    if ((self.shotPath || self.testPreviewPath) && self.shotPassNumber > 0) return self.shotPassNumber;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSNumber *issued = [defaults objectForKey:PassPreference];
    if ([issued isKindOfClass:NSNumber.class] && issued.integerValue < PassLegacyFloor) {
        return issued.integerValue;
    }
    // The slot the install falls into is the number, so installs are ordered
    // and separated without a server handing anything out.
    double elapsed = NSDate.date.timeIntervalSince1970 - PassEpoch;
    NSInteger number = PassFirstOpenNumber +
        (NSInteger)fmax(0., floor(elapsed / PassSlotSeconds));
    [defaults setInteger:number forKey:PassPreference];
    return number;
}

// No.02 is handed out rather than drawn, so its stone is picked instead of
// left to the number: a rounded block-family shape in the green hue band.
// Chosen by rendering candidates, because the silhouette comes from a
// per-view contour that the stone's ratio does not predict.
static const NSInteger PassAuthorSeed = 13612;

- (NSInteger)passStoneSeed {
    return self.passNumber == 2 ? PassAuthorSeed : self.passNumber;
}

- (NSInteger)passPaletteSeed {
    return self.passNumber == 2 ? PassAuthorSeed : self.passNumber;
}

- (NSString *)passConfigScript {
    if (self.journalPassStone) {
        return [NSString stringWithFormat:@"window.pebbleConfig = {staticPass:true, number:%ld, faces:%@, passStone:%@};",
            (long)self.passNumber, [self jsonForPebble:self.journalPassStone[@"faces"]],
            [self jsonForPebble:self.journalPassStone]];
    }
    // Both seeds are pinned and the user's choices deliberately left out, so the
    // card is the same stone in the same colour every time it is opened.
    return [NSString stringWithFormat:@"window.pebbleConfig = {seed: %ld, paletteSeed: %ld,"
            " texture: null, palette: null, faces: null, staticPass: true, number: %ld};",
            (long)self.passStoneSeed, (long)self.passPaletteSeed, (long)self.passNumber];
}

- (void)showJournalPass:(NSButton *)sender {
    if ((NSUInteger)sender.tag >= self.favorites.count) return;
    self.journalPassStone = self.favorites[sender.tag];
    [self showPaneAtIndex:PassPaneIndex];
}

- (void)showOriginalPass:(id)sender {
    self.journalPassStone = nil;
    [self showPaneAtIndex:PassPaneIndex];
}

- (NSView *)passPane {
    self.passRenderer = [self newRendererWithConfig:self.passConfigScript desktop:NO];
    NSView *card = [self stageAround:self.passRenderer height:440];

    NSView *actions = [self cardWithRows:@[
        [self rowWithSymbol:@"copy" title:@"复制编号"
                   subtitle:@"把 No. 编号复制到剪贴板"
                    control:[self actionButton:@"复制" action:@selector(copyPassNumber:)]],
    ]];
    if (self.journalPassStone) {
        NSView *back = [self cardWithRows:@[
            [self rowWithSymbol:nil title:@"来自石头日记" subtitle:self.journalPassStone[@"note"]
                       control:[self actionButton:@"返回原石头证" action:@selector(showOriginalPass:)]]
        ]];
        return [self paneWithCards:@[back, card, actions]];
    }
    return [self paneWithCards:@[card, actions]];
}

- (void)capturePassForVerification {
    NSString *script = @"const r=document.getElementById('root'), stone=document.getElementById('pass-stone');"
        "await stone.decode(); const frame=stone.src;"
        "r.querySelector('button').click();"
        "await new Promise(resolve=>setTimeout(resolve, 600));"
        "return {still:r.inert && stone.naturalWidth>0 && frame===stone.src,"
        "number:document.getElementById('pass-number').textContent,"
        "tone:document.documentElement.style.getPropertyValue('--pass-tone')};";
    [self.passRenderer callAsyncJavaScript:script arguments:@{} inFrame:nil
        inContentWorld:WKContentWorld.pageWorld completionHandler:^(NSDictionary *result, NSError *error) {
        NSString *expected = [NSString stringWithFormat:@"%02ld", (long)self.passNumber];
        if (error || ![result[@"still"] boolValue] || ![result[@"number"] isEqual:expected] ||
            ![result[@"tone"] length]) {
            NSLog(@"Stone pass verification failed: %@ %@", result, error);
            exit(5);
        }
        NSLog(@"Verified stone pass %@, glow RGB %@", expected, result[@"tone"]);
        [self.passRenderer takeSnapshotWithConfiguration:nil completionHandler:^(NSImage *image, NSError *snapshotError) {
            NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:image.TIFFRepresentation];
            NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            if (snapshotError || ![png writeToFile:self.shotPath atomically:YES]) exit(6);
            [NSApp terminate:nil];
        }];
    }];
}

- (void)copyPassNumber:(id)sender {
    NSPasteboard *board = NSPasteboard.generalPasteboard;
    [board clearContents];
    [board setString:[NSString stringWithFormat:@"No. %02ld", (long)self.passNumber]
             forType:NSPasteboardTypeString];
}

@end
