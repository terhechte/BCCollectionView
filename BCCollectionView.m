//  Created by Pieter Omvlee on 24/11/2010.
//  Copyright 2010 Bohemian Coding. All rights reserved.

#import "BCCollectionView.h"
#import "BCGeometryExtensions.h"
#import "BCCollectionViewLayoutManager.h"
#import "BCCollectionViewLayoutItem.h"
#import "BCCollectionViewGroup.h"

@interface BCCollectionView ()
- (void)configureView;
@end

//#define CDBG() NSLog(@"%@",[NSThread callStackSymbols]); NSLog(@"%s", _cmd); NSLog(@"------------------------");
#define CDBG() while (0) {};


@implementation BCCollectionView
@synthesize delegate, contentArray, groups, backgroundColor, originalSelectionIndexes, zoomValueObserverKey, accumulatedKeyStrokes, numberOfPreRenderedRows, layoutManager;
@dynamic visibleViewControllerArray;

- (id)initWithFrame:(NSRect)frameRect
{
  self = [super initWithFrame:frameRect];
  if (self) {
    [self configureView];
  }
  return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
  self = [super initWithCoder:aDecoder];
  if (self) {
    [self configureView];
  }
  return self;
}

- (void)configureView
{
  reusableViewControllers     = [[NSMutableArray alloc] init];
  visibleViewControllers      = [[NSMutableDictionary alloc] init];
  contentArray                = [[NSArray alloc] init];
  selectionIndexes            = [[NSMutableIndexSet alloc] init];
  dragHoverIndex              = NSNotFound;
  accumulatedKeyStrokes       = [[NSString alloc] init];
  numberOfPreRenderedRows     = 3;
  layoutManager               = [[BCCollectionViewLayoutManager alloc] initWithCollectionView:self];
  visibleGroupViewControllers = [[NSMutableDictionary alloc] init];

  [self addObserver:self forKeyPath:@"backgroundColor" options:0 context:NULL];

  NSClipView *enclosingClipView = [[self enclosingScrollView] contentView];
  [enclosingClipView setPostsBoundsChangedNotifications:YES];
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center addObserver:self selector:@selector(scrollViewDidScroll:) name:NSViewBoundsDidChangeNotification object:enclosingClipView];
  [center addObserver:self selector:@selector(viewDidResize) name:NSViewFrameDidChangeNotification object:self];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
  if ([keyPath isEqualToString:@"backgroundColor"])
    [self setNeedsDisplay:YES];
  else if ([keyPath isEqual:zoomValueObserverKey]) {
    if ([self respondsToSelector:@selector(zoomValueDidChange)])
      [self performSelector:@selector(zoomValueDidChange)];
  } else if ([keyPath isEqualToString:@"isCollapsed"]) {
    [self softReloadDataWithCompletionBlock:^{
      [self performSelector:@selector(scrollViewDidScroll:)];
    }];
  } else
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)dealloc
{
	[self removeObserver:self forKeyPath:@"backgroundColor"];
	if (zoomValueObserverKey !=	nil)
		[[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:zoomValueObserverKey];

  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center removeObserver:self name:NSViewBoundsDidChangeNotification object:[[self enclosingScrollView] contentView]];
  [center removeObserver:self name:NSViewFrameDidChangeNotification object:self];
  
  for (BCCollectionViewGroup *group in groups)
    [group removeObserver:self forKeyPath:@"isCollapsed"];
}

- (BOOL)isFlipped
{
  return YES;
}

#pragma mark Drawing Selections

- (BOOL)shoulDrawSelections
{
  if ([delegate respondsToSelector:@selector(collectionViewShouldDrawSelections:)])
    return [delegate collectionViewShouldDrawSelections:self];
  else
    return YES;
}

- (BOOL)shoulDrawHover
{
  if ([delegate respondsToSelector:@selector(collectionViewShouldDrawHover:)])
    return [delegate collectionViewShouldDrawHover:self];
  else
    return YES;
}

- (BOOL)shouldDrawSelectionRect
{
  if ([delegate respondsToSelector:@selector(collectionViewShouldDrawSelectionRect:)])
    return [delegate collectionViewShouldDrawSelectionRect:self];
  else
    return YES;
}

- (void)drawItemSelectionForInRect:(NSRect)aRect
{
  NSRect insetRect = NSInsetRect(aRect, 10, 10);
  if ([self needsToDrawRect:insetRect]) {
    [[NSColor lightGrayColor] set];
    [[NSBezierPath bezierPathWithRoundedRect:insetRect xRadius:10 yRadius:10] fill];
  }
}

- (void)drawRect:(NSRect)dirtyRect
{
  [backgroundColor ? backgroundColor : [NSColor whiteColor] set];
    NSRectFill(dirtyRect);

  if ([self shouldDrawSelectionRect]) {
    [[NSColor grayColor] set];
    NSFrameRect(BCRectFromTwoPoints(mouseDownLocation, mouseDraggedLocation));
  }

  if ([selectionIndexes count] > 0 && [self shoulDrawSelections]) {
    for (NSNumber *number in visibleViewControllers.copy)
      if ([selectionIndexes containsIndex:[number integerValue]])
        [self drawItemSelectionForInRect:[[[visibleViewControllers objectForKey:number] view] frame]];
  }
  
//  if (dragHoverIndex != NSNotFound && [self shoulDrawHover])
//    [self drawItemSelectionForInRect:[[[visibleViewControllers objectForKey:[NSNumber numberWithInteger:dragHoverIndex]] view] frame]];
}

#pragma mark Delegate Call Wrappers

- (void)delegateUpdateSelectionForItemAtIndex:(NSUInteger)index
{
    if ([contentArray count] <= index)return;
  if ([delegate respondsToSelector:@selector(collectionView:updateViewControllerAsSelected:forItem:)])
    [delegate collectionView:self updateViewControllerAsSelected:[self viewControllerForItemAtIndex:index]
               forItem:[contentArray objectAtIndex:index]];
}

- (void)delegateUpdateDeselectionForItemAtIndex:(NSUInteger)index
{
    if ([contentArray count] <= index)return;
  if ([delegate respondsToSelector:@selector(collectionView:updateViewControllerAsDeselected:forItem:)])
    [delegate collectionView:self updateViewControllerAsDeselected:[self viewControllerForItemAtIndex:index]
               forItem:[contentArray objectAtIndex:index]];
}

- (void)delegateCollectionViewSelectionDidChange
{
  if (!selectionChangedDisabled && [delegate respondsToSelector:@selector(collectionViewSelectionDidChange:)]) {
    [[NSRunLoop currentRunLoop] cancelPerformSelector:@selector(collectionViewSelectionDidChange:) target:delegate argument:self];
    [(id)delegate performSelector:@selector(collectionViewSelectionDidChange:) withObject:self afterDelay:0.0];
  }
}

- (void)delegateDidSelectItemAtIndex:(NSUInteger)index
{
  if ([delegate respondsToSelector:@selector(collectionView:didSelectItem:withViewController:)])
    [delegate collectionView:self
         didSelectItem:[contentArray objectAtIndex:index]
    withViewController:[self viewControllerForItemAtIndex:index]];
}

- (void)delegateDidDeselectItemAtIndex:(NSUInteger)index
{
  if ([delegate respondsToSelector:@selector(collectionView:didDeselectItem:withViewController:)])
    [delegate collectionView:self
       didDeselectItem:[contentArray objectAtIndex:index]
    withViewController:[self viewControllerForItemAtIndex:index]];
}

- (void)delegateViewControllerBecameInvisibleAtIndex:(NSUInteger)index
{
  if ([delegate respondsToSelector:@selector(collectionView:viewControllerBecameInvisible:)])
    [delegate collectionView:self viewControllerBecameInvisible:[self viewControllerForItemAtIndex:index]];
}

- (NSSize)cellSize
{
  return [delegate cellSizeForCollectionView:self];
}

- (NSUInteger)groupHeaderHeight
{
  return [delegate groupHeaderHeightForCollectionView:self];
}

- (NSIndexSet *)indexesOfItemsInRect:(NSRect)aRect
{
  NSArray *itemLayouts = [layoutManager itemLayouts];
  NSIndexSet *visibleIndexes = [itemLayouts indexesOfObjectsWithOptions:NSEnumerationConcurrent passingTest:^BOOL(id itemLayout, NSUInteger idx, BOOL *stop) {
      //return (NSPointInRect([itemLayout itemRect].origin, aRect));
      return (NSIntersectsRect([itemLayout itemRect], aRect));
  }];
  return visibleIndexes;
}

- (NSIndexSet *)indexesOfItemContentRectsInRect:(NSRect)aRect
{
  NSArray *itemLayouts = [layoutManager itemLayouts];
  NSIndexSet *visibleIndexes = [itemLayouts indexesOfObjectsWithOptions:NSEnumerationConcurrent passingTest:^BOOL(id itemLayout, NSUInteger idx, BOOL *stop) {
    return NSIntersectsRect([itemLayout itemRect], aRect);
  }];
  return visibleIndexes;
}

- (NSRange)rangeOfVisibleItems
{
  NSIndexSet *visibleIndexes = [self indexesOfItemsInRect:[self visibleRect]];
//    NSLog(@"************ rangeOfVisibleIndexes: %@", visibleIndexes);
//    NSLog(@"************ self-sizse: %@ superview-size: %@", [NSValue valueWithRect:self.frame],
//          [NSValue valueWithRect:self.superview.frame]);
  return NSMakeRange([visibleIndexes firstIndex], [visibleIndexes lastIndex]-[visibleIndexes firstIndex]);
}

- (NSRange)rangeOfVisibleItemsWithOverflow
{
  NSRange range = [self rangeOfVisibleItems];
  NSInteger extraItems = [layoutManager maximumNumberOfItemsPerRow] * numberOfPreRenderedRows;
  NSInteger min = range.location;
  NSUInteger max = range.location + range.length;
  
  min = MAX(0, min-extraItems);
  max = MIN([contentArray count], max+extraItems);
  return NSMakeRange(min, max-min);
}

#pragma mark Querying ViewControllers

- (NSIndexSet *)indexesOfViewControllers
{
  NSMutableIndexSet *set = [NSMutableIndexSet indexSet];
  for (NSNumber *number in [visibleViewControllers allKeys])
    [set addIndex:[number integerValue]];
  return set;
}

- (NSArray *)visibleViewControllerArray
{
  return [visibleViewControllers allValues];
}

- (NSIndexSet *)indexesOfInvisibleViewControllers
{
  NSRange visibleRange = [self rangeOfVisibleItemsWithOverflow];
  return [[self indexesOfViewControllers] indexesPassingTest:^BOOL(NSUInteger idx, BOOL *stop) {
    return !NSLocationInRange(idx, visibleRange);
  }];
}

- (NSViewController *)viewControllerForItemAtIndex:(NSUInteger)index
{
  return [visibleViewControllers objectForKey:[NSNumber numberWithInteger:index]];
}

- (NSIndexSet*)indexesOfMissingViewControllers
{
    return [[NSIndexSet indexSetWithIndexesInRange:[self rangeOfVisibleItemsWithOverflow]] indexesPassingTest:^BOOL(NSUInteger idx, BOOL *stop) {
		return (![visibleViewControllers objectForKey:[NSNumber numberWithInteger:idx]]);
    }];
}

#pragma mark Swapping ViewControllers in and out

- (void)removeViewControllerForItemAtIndex:(NSUInteger)anIndex
{
//	NSLog(@"removing view controller at index %lu", anIndex);
  NSNumber *key = [NSNumber numberWithInteger:anIndex];
  NSViewController *viewController = [visibleViewControllers objectForKey:key];
    @try {
        // Terminating app due to uncaught exception 'NSRangeException', reason: 'Cannot remove an observer <NSScrollView 0x6000001dd1f0> for the key path "contentLayoutRect" from <NSWindow 0x6080001f3b00> because it is not registered as an observer.'
        [[viewController view] removeFromSuperview];
    }
    @catch (NSException *exception) {
    }
  
  [self delegateUpdateDeselectionForItemAtIndex:anIndex];
  [self delegateViewControllerBecameInvisibleAtIndex:anIndex];
  
  if (viewController != nil)
      [reusableViewControllers addObject:viewController];
  [visibleViewControllers removeObjectForKey:key];
}


- (void)removeInvisibleViewControllers
{
//	NSLog(@"removeInvisibleViewControllers dispatch");
  [[self indexesOfInvisibleViewControllers] enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
    [self removeViewControllerForItemAtIndex:idx];
  }];
}

- (NSViewController *)emptyViewControllerForInsertion
{
  if ([reusableViewControllers count] > 0) {
    NSViewController *viewController = [reusableViewControllers lastObject];
    [reusableViewControllers removeLastObject];
    return viewController;
  } else
    return [delegate reusableViewControllerForCollectionView:self];
}

- (void)addMissingViewControllerForItemAtIndex:(NSUInteger)anIndex withFrame:(NSRect)aRect
{
	if (anIndex < [contentArray count]) {
		NSViewController *viewController = [self emptyViewControllerForInsertion];
		if (viewController != nil) {
//			NSLog(@"adding view controller at index %lu", anIndex);
			[visibleViewControllers setObject:viewController forKey:[NSNumber numberWithInteger:anIndex]];
			[[viewController view] setFrame:aRect];
			[[viewController view] setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
            //NSLog(@"place view controller in: %@", [NSValue valueWithRect:aRect]);

			id itemToLoad = [contentArray objectAtIndex:anIndex];
			[delegate collectionView:self willShowViewController:viewController forItem:itemToLoad atIndex:anIndex];
			[self addSubview:[viewController view]];
            /*dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.02 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [viewController.view setNeedsDisplay:YES];
                [viewController.view.layer setNeedsDisplay];
            });*/
			if ([selectionIndexes containsIndex:anIndex])
			[self delegateUpdateSelectionForItemAtIndex:anIndex];
		}
	}
}

- (void)addMissingGroupHeaders
{
  if ([groups count] > 0) {
    [groups enumerateObjectsUsingBlock:^(id group, NSUInteger idx, BOOL *stop) {
      NSRect groupRect = NSMakeRect(0, NSMinY([layoutManager rectOfItemAtIndex:[group itemRange].location])-[self groupHeaderHeight], NSWidth([self visibleRect]), [self groupHeaderHeight]);
      if (idx == 0 && ![group isCollapsed] && [delegate respondsToSelector:@selector(topOffsetForItemsInCollectionView:)])
        groupRect.origin.y -= [delegate topOffsetForItemsInCollectionView:self];
      
      BOOL groupShouldBeVisible = NSIntersectsRect(groupRect, [self visibleRect]);
      NSViewController *groupViewController = [visibleGroupViewControllers objectForKey:[NSNumber numberWithInteger:idx]];
      [[groupViewController view] setFrame:groupRect];
      if (groupShouldBeVisible && !groupViewController) {
        groupViewController = [delegate collectionView:self headerForGroup:group];
        [self addSubview:[groupViewController view]];
        [visibleGroupViewControllers setObject:groupViewController forKey:[NSNumber numberWithInteger:idx]];
        [[groupViewController view] setFrame:groupRect];
      } else if (!groupShouldBeVisible && groupViewController) {
          @try {
              [[groupViewController view] removeFromSuperview];
          }
          @catch (NSException *exception) {
          }
        [visibleGroupViewControllers removeObjectForKey:[NSNumber numberWithInteger:idx]];
      }
    }];
  }
}

- (void)addMissingViewControllersToView
{
    [[NSIndexSet indexSetWithIndexesInRange:[self rangeOfVisibleItemsWithOverflow]] enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
      if (![visibleViewControllers objectForKey:[NSNumber numberWithInteger:idx]]) {
        [self addMissingViewControllerForItemAtIndex:idx withFrame:[layoutManager rectOfItemAtIndex:idx]];
      }
    }];
    [self addMissingGroupHeaders];
}

- (void)moveViewControllersToProperPosition
{
  for (NSNumber *number in visibleViewControllers) {
    NSRect r = [layoutManager rectOfItemAtIndex:[number integerValue]];
    if (!NSEqualRects(r, NSZeroRect))
      [[[visibleViewControllers objectForKey:number] view] setFrame:r];
  }
}

#pragma mark Selecting and Deselecting Items

- (void)selectItemAtIndex:(NSUInteger)index
{
  [self selectItemAtIndex:index inBulk:NO];
}

- (void)selectItemAtIndex:(NSUInteger)index inBulk:(BOOL)bulkSelecting
{
  if (index >= [contentArray count])
    return;
    
  BOOL maySelectItem = YES;
  NSViewController *viewController = [self viewControllerForItemAtIndex:index];
  id item = [contentArray objectAtIndex:index];
  
  if ([delegate respondsToSelector:@selector(collectionView:shouldSelectItem:withViewController:)])
    maySelectItem = [delegate collectionView:self shouldSelectItem:item withViewController:viewController];
  
  if (maySelectItem) {
    [selectionIndexes addIndex:index];
    [self delegateUpdateSelectionForItemAtIndex:index];
    [self delegateDidSelectItemAtIndex:index];
    if (!bulkSelecting)
      [self delegateCollectionViewSelectionDidChange];
    if ([self shoulDrawSelections])
      [self setNeedsDisplayInRect:[layoutManager rectOfItemAtIndex:index]];
  }
  
  if (!bulkSelecting)
    lastSelectionIndex = index;
}

- (void)selectItemsAtIndexes:(NSIndexSet *)indexes
{
  [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
    [self selectItemAtIndex:idx inBulk:YES];
  }];
  lastSelectionIndex = [indexes firstIndex];
  [self delegateCollectionViewSelectionDidChange];
}

- (void)deselectItemAtIndex:(NSUInteger)index
{
  [self deselectItemAtIndex:index inBulk:NO];
}

- (void)deselectItemAtIndex:(NSUInteger)index inBulk:(BOOL)bulkDeselecting
{
  if (index < [contentArray count]) {
    [selectionIndexes removeIndex:index];
    if ([self shoulDrawSelections])
      [self setNeedsDisplayInRect:[layoutManager rectOfItemAtIndex:index]];
    
    if (!bulkDeselecting)
      [self delegateCollectionViewSelectionDidChange];
    [self delegateDidDeselectItemAtIndex:index];
    [self delegateUpdateDeselectionForItemAtIndex:index];
  }
}

- (void)deselectItemsAtIndexes:(NSIndexSet *)indexes
{
  [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
    [self deselectItemAtIndex:idx inBulk:YES];
  }];
  [self delegateCollectionViewSelectionDidChange];
}

- (void)deselectAllItems
{
  [self deselectItemsAtIndexes:[selectionIndexes copy]];
}

- (NSIndexSet *)selectionIndexes
{
  return selectionIndexes;
}

- (void)selectAll:(id)sender
{
  [self selectItemsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,[contentArray count])]];
}

#pragma mark User-interaction

- (BOOL)acceptsFirstResponder
{
  return YES;
}

- (BOOL)canBecomeKeyView
{
  return YES;
}

#pragma mark Reloading and Updating the Icon View

- (void)softReloadVisibleViewControllers
{
   CDBG()
  NSMutableArray *removeKeys = [NSMutableArray array];
  
  for (NSString *number in visibleViewControllers.copy) {
    NSUInteger index             = [number integerValue];
    NSViewController *controller = [visibleViewControllers objectForKey:number];
      
      if (!controller)continue;
    
    if (index < [contentArray count]) {
      if ([selectionIndexes containsIndex:index])
        [self delegateUpdateDeselectionForItemAtIndex:index];
      [delegate collectionView:self willShowViewController:controller forItem:[contentArray objectAtIndex:index] atIndex:index];
    } else {
      if ([selectionIndexes containsIndex:index])
        [self delegateUpdateDeselectionForItemAtIndex:index];
      
      [self delegateViewControllerBecameInvisibleAtIndex:index];
      [[controller view] removeFromSuperview];
      [reusableViewControllers addObject:controller];
      [removeKeys addObject:number];
    }
  }
  [visibleViewControllers removeObjectsForKeys:removeKeys];
}

- (void)resizeFrameToFitContents
{
  NSRect frame = [self frame];
  frame.size.height = [self visibleRect].size.height;
  if ([contentArray count] > 0) {
    BCCollectionViewLayoutItem *layoutItem = [[layoutManager itemLayouts] lastObject];
    frame.size.height = MAX(frame.size.height, NSMaxY([layoutItem itemRect]));
  }
  [self setFrame:frame];
}

- (void)reloadDataWithItems:(NSArray *)newContent emptyCaches:(BOOL)shouldEmptyCaches
{
  [self reloadDataWithItems:newContent groups:nil emptyCaches:shouldEmptyCaches];
}

- (void)reloadDataWithItems:(NSArray *)newContent groups:(NSArray *)newGroups emptyCaches:(BOOL)shouldEmptyCaches
{
  [self reloadDataWithItems:newContent groups:newGroups emptyCaches:shouldEmptyCaches completionBlock:^{}];
}

- (void)reloadDataWithItems:(NSArray *)newContent groups:(NSArray *)newGroups emptyCaches:(BOOL)shouldEmptyCaches completionBlock:(dispatch_block_t)completionBlock
{
    
   CDBG()
  // soft reload usually means we added items to the view. which is why we won't deselect then
    if (shouldEmptyCaches)
        [self deselectAllItems];
    
  [layoutManager cancelItemEnumerator];
  
  if (!delegate)
    return;
  
  //NSSize cellSize = [delegate cellSizeForCollectionView:self];
  //if (NSWidth([self frame]) < cellSize.width || NSHeight([self frame]) < cellSize.height)
  //  return;
  
  for (BCCollectionViewGroup *group in groups)
    [group removeObserver:self forKeyPath:@"isCollapsed"];
  for (BCCollectionViewGroup *group in newGroups)
    [group addObserver:self forKeyPath:@"isCollapsed" options:0 context:NULL];
  
  self.groups       = newGroups;
  self.contentArray = newContent;
  
    for (NSViewController *viewController in [visibleGroupViewControllers allValues]) {
        @try {
            [[viewController view] removeFromSuperview];
        }
        @catch (NSException *exception) {
        }
    }
  [visibleGroupViewControllers removeAllObjects];
  
  if (shouldEmptyCaches) {
    for (NSViewController *viewController in [visibleViewControllers allValues]) {
        @try {
            [[viewController view] removeFromSuperview];
        }
        @catch (NSException *exception) {
        }
      if ([delegate respondsToSelector:@selector(collectionView:viewControllerBecameInvisible:)])
        [delegate collectionView:self viewControllerBecameInvisible:viewController];
    }
    
    [reusableViewControllers removeAllObjects];
    [visibleViewControllers removeAllObjects];
  } else
    [self softReloadVisibleViewControllers];
  
    if (shouldEmptyCaches)
        [selectionIndexes removeAllIndexes];
  
  NSRect visibleRect = [self visibleRect];
  [layoutManager enumerateItems:^(BCCollectionViewLayoutItem *layoutItem) {
    NSViewController *viewController = [self viewControllerForItemAtIndex:[layoutItem itemIndex]];
    if (viewController) {
      [[viewController view] setFrame:[layoutItem itemRect]];
      [delegate collectionView:self willShowViewController:viewController forItem:[contentArray objectAtIndex:[layoutItem itemIndex]] atIndex:[layoutItem itemIndex]];
    } else if (NSIntersectsRect([layoutItem itemRect], visibleRect))
      [self addMissingViewControllerForItemAtIndex:[layoutItem itemIndex] withFrame:[layoutItem itemRect]];
  } completionBlock:^{
    [self resizeFrameToFitContents];
    [self addMissingGroupHeaders];
    dispatch_async(dispatch_get_main_queue(), completionBlock);
  }];
}

- (void)scrollViewDidScroll:(NSNotification *)note
{
	if ([[self indexesOfInvisibleViewControllers] count] > 0)
	{
		[self removeInvisibleViewControllers];
	}
	if ([[self indexesOfMissingViewControllers] count] > 0)
	{
			[self addMissingViewControllersToView];
	}
    [self addMissingGroupHeaders];
  if ([delegate respondsToSelector:@selector(collectionViewDidScroll:inDirection:)]) {
    if ([self visibleRect].origin.y > previousFrameBounds.origin.y)
      [delegate collectionViewDidScroll:self inDirection:BCCollectionViewScrollDirectionDown];
    else
      [delegate collectionViewDidScroll:self inDirection:BCCollectionViewScrollDirectionUp];
    previousFrameBounds = [self visibleRect];
  }
}

- (void)viewDidResize
{
  if ([contentArray count] > 0 && [visibleViewControllers count] > 0)
    [self softReloadDataWithCompletionBlock:NULL];
}

- (void)softReloadDataWithCompletionBlock:(dispatch_block_t)block
{
  //NSSize cellSize = [delegate cellSizeForCollectionView:self];
  //if (NSWidth([self visibleRect]) < cellSize.width) // || NSHeight([self visibleRect]) < cellSize.height
  //  return;
  
   //CDBG()
    
  NSRange range = [self rangeOfVisibleItemsWithOverflow];
  [layoutManager enumerateItems:^(BCCollectionViewLayoutItem *layoutItem) {
    if (NSLocationInRange([layoutItem itemIndex], range)) {
      NSViewController *controller = [self viewControllerForItemAtIndex:[layoutItem itemIndex]];
      if (controller)
        [[controller view] setFrame:[layoutItem itemRect]];
      else
        [self addMissingViewControllerForItemAtIndex:[layoutItem itemIndex] withFrame:[layoutItem itemRect]];
    } else {
      if ([self viewControllerForItemAtIndex:[layoutItem itemIndex]])
        [self removeViewControllerForItemAtIndex:[layoutItem itemIndex]];
    }
  } completionBlock:^(void) {
    [self resizeFrameToFitContents];
    [self addMissingGroupHeaders];
    [self setNeedsDisplay:YES];
    if (block != NULL)
      block();
  }];
}

- (void)clearViewControllerCache {
    [reusableViewControllers removeAllObjects];
}

- (NSMenu *)menuForEvent:(NSEvent *)anEvent
{
  [self mouseDown:anEvent];
  
  if ([delegate respondsToSelector:@selector(collectionView:menuForItemsAtIndexes:)])
    return [delegate collectionView:self menuForItemsAtIndexes:[self selectionIndexes]];
  else
    return nil;
}

- (BOOL)resignFirstResponder
{
  if ([delegate respondsToSelector:@selector(collectionViewLostFirstResponder:)])
    [delegate collectionViewLostFirstResponder:self];
  return [super resignFirstResponder];
}

- (BOOL)becomeFirstResponder
{
  if ([delegate respondsToSelector:@selector(collectionViewBecameFirstResponder:)])
    [delegate collectionViewBecameFirstResponder:self];
  return [super becomeFirstResponder];
}

- (BOOL)isOpaque
{
  return YES;
}

@end
