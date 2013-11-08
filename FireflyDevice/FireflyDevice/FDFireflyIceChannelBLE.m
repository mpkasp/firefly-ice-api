//
//  FDFireflyIceChannelBLE.m
//  Sync
//
//  Created by Denis Bohm on 4/3/13.
//  Copyright (c) 2013 Firefly Design. All rights reserved.
//

#import "FDBinary.h"
#import "FDDetour.h"
#import "FDDetourSource.h"
#import "FDFireflyIceChannelBLE.h"

#if TARGET_OS_IPHONE
#import <CoreBluetooth/CoreBluetooth.h>
#else
#import <IOBluetooth/IOBluetooth.h>
#endif

@implementation FDFireflyIceChannelBLERSSI

+ (FDFireflyIceChannelBLERSSI *)RSSI:(float)value date:(NSDate *)date
{
    FDFireflyIceChannelBLERSSI *RSSI = [[FDFireflyIceChannelBLERSSI alloc] init];
    RSSI.value = value;
    RSSI.date = date;
    return RSSI;
}

+ (FDFireflyIceChannelBLERSSI *)RSSI:(float)value
{
    return [FDFireflyIceChannelBLERSSI RSSI:value date:[NSDate date]];
}

@end

@interface FDFireflyIceChannelBLE () <CBPeripheralDelegate>

@property FDFireflyIceChannelStatus status;

@property CBCentralManager *centralManager;
@property CBPeripheral *peripheral;
@property CBCharacteristic *characteristic;
@property FDDetour *detour;
@property NSMutableArray *detourSources;
@property BOOL writePending;

@end

@implementation FDFireflyIceChannelBLE

- (id)initWithCentralManager:(CBCentralManager *)centralManager withPeripheral:(CBPeripheral *)peripheral
{
    if (self = [super init]) {
        _centralManager = centralManager;
        _peripheral = peripheral;
        _peripheral.delegate = self;
        _detour = [[FDDetour alloc] init];
        _detourSources = [NSMutableArray array];
    }
    return self;
}

- (NSString *)name
{
    return @"BLE";
}


- (void)open
{
    [_centralManager connectPeripheral:_peripheral options:nil];
}

- (void)close
{
    [_centralManager cancelPeripheralConnection:_peripheral];
}

- (void)didConnectPeripheral
{
    [_peripheral discoverServices:nil];
    self.status = FDFireflyIceChannelStatusOpening;
    if ([_delegate respondsToSelector:@selector(fireflyIceChannel:status:)]) {
        [_delegate fireflyIceChannel:self status:self.status];
    }
}

- (void)didDisconnectPeripheralError:(NSError *)error
{
    [_detour clear];
    self.status = FDFireflyIceChannelStatusClosed;
    if ([_delegate respondsToSelector:@selector(fireflyIceChannel:status:)]) {
        [_delegate fireflyIceChannel:self status:self.status];
    }
}

- (void)didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    //    NSLog(@"didWriteValueForCharacteristic %@", error);
    _writePending = NO;
    [self checkWrite];
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    __weak FDFireflyIceChannelBLE *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf didWriteValueForCharacteristic:characteristic error:error];
    });
}

- (void)didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
//    NSLog(@"didUpdateValueForCharacteristic %@ %@", characteristic.value, error);
    [_detour detourEvent:characteristic.value];
    if (_detour.state == FDDetourStateSuccess) {
        if ([_delegate respondsToSelector:@selector(fireflyIceChannelPacket:data:)]) {
            [_delegate fireflyIceChannelPacket:self data:_detour.data];
        }
        [_detour clear];
    } else
    if (_detour.state == FDDetourStateError) {
        if ([_delegate respondsToSelector:@selector(fireflyIceChannel:detour:error:)]) {
            [_delegate fireflyIceChannel:self detour:_detour error:_detour.error];
        }
        [_detour clear];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    __weak FDFireflyIceChannelBLE *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf didUpdateValueForCharacteristic:characteristic error:error];
    });
}

- (void)checkWrite
{
    while (_detourSources.count > 0) {
        FDDetourSource *detourSource = [_detourSources objectAtIndex:0];
        NSData *subdata = [detourSource next];
        if (subdata != nil) {
            [_peripheral writeValue:subdata forCharacteristic:_characteristic type:CBCharacteristicWriteWithResponse];
            _writePending = YES;
            break;
        }
        [_detourSources removeObjectAtIndex:0];
    }
}

- (void)fireflyIceChannelSend:(NSData *)data
{
    [_detourSources addObject:[[FDDetourSource alloc] initWithSize:20 data:data]];
    [self checkWrite];
}

- (void)didDiscoverServices:(NSError *)error
{
//    NSLog(@"didDiscoverServices %@", peripheral.name);
    for (CBService *service in _peripheral.services) {
//        NSLog(@"didDiscoverService %@", service.UUID);
        [_peripheral discoverCharacteristics:nil forService:service];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    __weak FDFireflyIceChannelBLE *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf didDiscoverServices:error];
    });
}

- (void)didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    CBUUID *characteristicUUID = [CBUUID UUIDWithString:@"310a0002-1b95-5091-b0bd-b7a681846399"];
//    NSLog(@"didDiscoverCharacteristicsForService %@", service.UUID);
    for (CBCharacteristic *characteristic in service.characteristics) {
//        NSLog(@"didDiscoverServiceCharacteristic %@", characteristic.UUID);
        if ([characteristicUUID isEqual:characteristic.UUID]) {
//            NSLog(@"found characteristic value");
            _characteristic = characteristic;
            
            [_peripheral setNotifyValue:YES forCharacteristic:_characteristic];
            
            self.status = FDFireflyIceChannelStatusOpen;
            if ([_delegate respondsToSelector:@selector(fireflyIceChannel:status:)]) {
                [_delegate fireflyIceChannel:self status:self.status];
            }
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    __weak FDFireflyIceChannelBLE *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf didDiscoverCharacteristicsForService:service error:error];
    });
}

- (void)didUpdateRSSI:(NSError *)error
{
    self.RSSI = [FDFireflyIceChannelBLERSSI RSSI:[_peripheral.RSSI floatValue]];
}

- (void)peripheralDidUpdateRSSI:(CBPeripheral *)peripheral error:(NSError *)error
{
    __weak FDFireflyIceChannelBLE *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf didUpdateRSSI:error];
    });
}

@end
