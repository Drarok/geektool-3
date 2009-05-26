/* LogWindowController */

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import "LogWindow.h"

@interface LogWindowController : NSWindowController
{
    IBOutlet id text;
    IBOutlet id scrollView;
    IBOutlet id picture;
    IBOutlet id logView;
    IBOutlet id quartzView;
    int		type;
    int ident;
    //bool rc = NO;
}
- (void)setIdent:(int)value;
- (int)ident;
- (id)logView;
- (id)quartzView;
- (void)setFont:(NSFont*)font;
- (void)setShadowText:(bool)shadow;
- (void)setTextBackgroundColor:(NSColor*)color;
- (void)setTextColor:(NSColor*)color;
- (void)setTextAlignment:(int)alignment;
- (void)setFrame:(NSRect)logWindowRect display:(bool)flag;
- (void)setHasShadow:(bool)flag;
- (void)setOpaque:(bool)flag;
- (void)setAutodisplay:(BOOL)value;
- (void)setLevel: (int)level;
- (void)makeKeyAndOrderFront: (id)sender;
- (void)display;
- (void)windowWillClose:(NSNotification *)aNotification;
- (void)addText:(NSString*)newText clear:(BOOL)clear;
- (void)scrollEnd;
- (void)setHighlighted:(BOOL)flag;
- (void)setWrap:(BOOL)wrap;
- (void)setFit:(int)fit;
- (void)setCrop:(BOOL)crop;
- (void)setPictureAlignment:(int)alignment;
- (void)setTextRect:(NSRect)rect;
- (void)setImage:(NSImage*)anImage;
- (void)setType:(int)anInt;
- (int)type;
- (void)setAttributes:(NSDictionary*)attributes;
- (void)setSticky:(BOOL)flag;
@end
