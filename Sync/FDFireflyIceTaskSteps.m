//
//  FDFireflyIceTaskSteps.m
//  Sync
//
//  Created by Denis Bohm on 9/14/13.
//  Copyright (c) 2013 Firefly Design. All rights reserved.
//

#import "FDFireflyIceCoder.h"
#import "FDFireflyIceTaskSteps.h"

#import <FireflyProduction/FDBinary.h>

@interface FDFireflyIceTaskSteps ()

@property NSInvocation *invocation;
@property uint32_t invocationId;

@end

@implementation FDFireflyIceTaskSteps

@synthesize timeout = _timeout;
@synthesize priority = _priority;
@synthesize isSuspended = _isSuspended;

- (id)init
{
    if (self = [super init]) {
        _timeout = 600; // !!! just for testing -denis
    }
    return self;
}

- (void)taskStarted
{
    NSLog(@"task started");
    [_firefly.observable addObserver:self];
}

- (void)taskSuspended
{
    NSLog(@"task suspended");
    [_firefly.observable removeObserver:self];
}

- (void)taskResumed
{
    NSLog(@"task resumed");
    [_firefly.observable addObserver:self];
}

- (void)taskCompleted
{
    NSLog(@"task completed");
    [_firefly.observable removeObserver:self];
}

- (void)fireflyIcePing:(id<FDFireflyIceChannel>)channel data:(NSData *)data
{
    NSLog(@"ping received");
    FDBinary *binary = [[FDBinary alloc] initWithData:data];
    uint32_t invocationId = [binary getUInt32];
    if (invocationId != _invocationId) {
        NSLog(@"unexpected ping");
        return;
    }
    
    if (_invocation != nil) {
        NSLog(@"invoking step %@", NSStringFromSelector(_invocation.selector));
        NSInvocation *invocation = _invocation;
        _invocation = nil;
        [invocation invoke];
    } else {
        NSLog(@"all steps completed");
        [_firefly.executor complete:self];
    }
}

- (NSInvocation *)invocation:(SEL)selector
{
    NSMethodSignature *signature = [[self class] instanceMethodSignatureForSelector:selector];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:self];
    [invocation setSelector:selector];
    return invocation;
}

- (void)next:(SEL)selector
{
    NSLog(@"queing next step %@", NSStringFromSelector(selector));
    
    [_firefly.executor feedWatchdog:self];
    
    _invocation = [self invocation:selector];
    _invocationId = arc4random_uniform(0xffffffff);
    
    FDBinary *binary = [[FDBinary alloc] init];
    [binary putUInt32:_invocationId];
    NSData *data = [binary dataValue];
    [_firefly.coder sendPing:_channel data:data];
}

- (void)done
{
    NSLog(@"task done");
    [_firefly.executor complete:self];
}

@end
