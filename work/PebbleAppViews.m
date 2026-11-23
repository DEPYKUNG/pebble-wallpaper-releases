#import "PebbleAppInternal.h"

@implementation PebbleFlippedView
- (BOOL)isFlipped {
    return YES;
}
@end

@implementation PebbleRoundedView
- (void)drawRect:(NSRect)rect {
    if (self.fill && self.fill != NSColor.clearColor) {
        [self.fill setFill];
        [[NSBezierPath bezierPathWithRoundedRect:self.bounds
                                         xRadius:self.radius yRadius:self.radius] fill];
    }
    if (!self.stroke) return;
    NSBezierPath *edge = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, .5, .5)
                                                        xRadius:self.radius yRadius:self.radius];
    edge.lineWidth = 1;
    [self.stroke setStroke];
    [edge stroke];
}
- (void)setFill:(NSColor *)fill {
    _fill = fill;
    self.needsDisplay = YES;
}
@end

@implementation PebbleDesktopButton
- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}
@end

@implementation PebbleRendererRecovery
@end
