#import "PebbleChangelogView.h"
#import <math.h>

@interface PebbleChangelogSummary : NSTextField
@end
@implementation PebbleChangelogSummary
- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    if (size.width > 0 && fabs(self.preferredMaxLayoutWidth - size.width) > .5) {
        self.preferredMaxLayoutWidth = size.width;
        [self invalidateIntrinsicContentSize];
    }
}
@end

@interface PebbleChangelogRail : NSView
@property BOOL first, last;
@end
@implementation PebbleChangelogRail
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)rect {
    [NSColor.separatorColor setStroke];
    NSBezierPath *line = [NSBezierPath bezierPath]; line.lineWidth = 1;
    [line moveToPoint:NSMakePoint(6.5, self.first ? 9 : 0)];
    [line lineToPoint:NSMakePoint(6.5, self.last ? 9 : NSHeight(self.bounds))]; [line stroke];
    [NSColor.linkColor setFill]; NSRectFill(NSMakeRect(3.5, 6, 6, 6));
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES;
}
@end

@implementation PebbleChangelogView
- (instancetype)initWithEntries:(NSArray *)entries currentVersion:(NSString *)version viewAllButton:(NSButton *)button {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.accessibilityIdentifier = @"recent-release-log";
    NSTextField *title = [NSTextField labelWithString:@"更新日志"];
    title.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
    NSTextField *current = [NSTextField labelWithString:[@"当前版本 v" stringByAppendingString:version]];
    current.font = [NSFont systemFontOfSize:11]; current.textColor = NSColor.secondaryLabelColor;
    NSView *space = [NSView new];
    NSStackView *heading = [NSStackView stackViewWithViews:@[title, space, current, button]];
    heading.orientation = NSUserInterfaceLayoutOrientationHorizontal; heading.spacing = 10;
    heading.alignment = NSLayoutAttributeCenterY;
    [space.widthAnchor constraintGreaterThanOrEqualToConstant:4].active = YES;
    [title setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [current setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [button setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *list = [NSStackView stackViewWithViews:@[]];
    list.orientation = NSUserInterfaceLayoutOrientationVertical; list.alignment = NSLayoutAttributeLeading; list.spacing = 0;
    NSMutableArray *valid = [NSMutableArray array];
    for (id entry in [entries isKindOfClass:NSArray.class] ? entries : @[]) {
        if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"version"] isKindOfClass:NSString.class] ||
            ![entry[@"summary"] isKindOfClass:NSString.class] || ![entry[@"build"] isKindOfClass:NSNumber.class]) continue;
        [valid addObject:entry]; if (valid.count == 3) break;
    }
    [valid enumerateObjectsUsingBlock:^(NSDictionary *entry, NSUInteger index, BOOL *stop) {
        NSView *row = [NSView new]; row.translatesAutoresizingMaskIntoConstraints = NO;
        PebbleChangelogRail *rail = [PebbleChangelogRail new]; rail.translatesAutoresizingMaskIntoConstraints = NO;
        rail.first = index == 0; rail.last = index == valid.count - 1;
        NSTextField *release = [NSTextField labelWithString:[NSString stringWithFormat:@"v%@ · Build %@", entry[@"version"], entry[@"build"]]];
        release.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightMedium];
        release.accessibilityIdentifier = @"changelog-version";
        PebbleChangelogSummary *summary = [PebbleChangelogSummary wrappingLabelWithString:entry[@"summary"]];
        summary.font = [NSFont systemFontOfSize:12]; summary.textColor = NSColor.secondaryLabelColor;
        summary.maximumNumberOfLines = 0; summary.preferredMaxLayoutWidth = 360; summary.selectable = YES;
        summary.accessibilityIdentifier = @"changelog-summary";
        [summary setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [summary setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
        NSStackView *text = [NSStackView stackViewWithViews:@[release, summary]];
        text.orientation = NSUserInterfaceLayoutOrientationVertical; text.alignment = NSLayoutAttributeLeading; text.spacing = 7;
        text.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:rail]; [row addSubview:text]; [list addArrangedSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.widthAnchor constraintEqualToAnchor:list.widthAnchor],
            [rail.topAnchor constraintEqualToAnchor:row.topAnchor], [rail.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
            [rail.leadingAnchor constraintEqualToAnchor:row.leadingAnchor], [rail.widthAnchor constraintEqualToConstant:13],
            [text.topAnchor constraintEqualToAnchor:row.topAnchor], [text.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-18],
            [text.leadingAnchor constraintEqualToAnchor:rail.trailingAnchor constant:10], [text.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [summary.widthAnchor constraintEqualToAnchor:text.widthAnchor],
        ]];
    }];
    if (!valid.count) [list addArrangedSubview:[NSTextField labelWithString:@"暂无更新记录"]];
    NSStackView *column = [NSStackView stackViewWithViews:@[heading, list]];
    column.orientation = NSUserInterfaceLayoutOrientationVertical; column.alignment = NSLayoutAttributeLeading; column.spacing = 17;
    column.translatesAutoresizingMaskIntoConstraints = NO; [self addSubview:column];
    [NSLayoutConstraint activateConstraints:@[
        [column.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16], [column.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [column.topAnchor constraintEqualToAnchor:self.topAnchor constant:16], [column.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-2],
        [heading.widthAnchor constraintEqualToAnchor:column.widthAnchor], [list.widthAnchor constraintEqualToAnchor:column.widthAnchor],
    ]];
    return self;
}
@end
