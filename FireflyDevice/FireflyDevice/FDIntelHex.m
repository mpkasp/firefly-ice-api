//
//  FDIntelHex.m
//  FireflyDevice
//
//  Created by Denis Bohm on 9/18/13.
//  Copyright (c) 2013-2014 Firefly Design LLC / Denis Bohm. All rights reserved.
//

#import "FDIntelHex.h"

#import "FDJSON.h"

@implementation FDIntelHexChunk

+ (FDIntelHexChunk *)chunk:(uint32_t)address data:(NSData *)data
{
    FDIntelHexChunk *chunk = [[FDIntelHexChunk alloc] init];
    chunk.address = address;
    chunk.data = data;
    return chunk;
}

+ (FDIntelHexChunk *)chunk:(uint32_t)address bytes:(uint8_t *)bytes length:(uint32_t)length
{
    return [FDIntelHexChunk chunk:address data:[NSData dataWithBytes:bytes length:length]];
}

@end

@implementation FDIntelHex

+ (FDIntelHex *)intelHex:(NSString *)hex address:(uint32_t)address length:(uint32_t)length
{
    FDIntelHex *intelHex = [[FDIntelHex alloc] init];
    [intelHex read:hex address:address length:length];
    return intelHex;
}

+ (NSData *)parse:(NSString *)content address:(uint32_t)address length:(uint32_t)length
{
    return [FDIntelHex intelHex:content address:address length:length].data;
}

+ (uint32_t)hex:(NSString *)line index:(int *)index length:(int)length crc:(uint8_t *)crc
{
    NSString *string = [line substringWithRange:NSMakeRange(*index, length)];
    *index += length;
    NSScanner *scanner = [NSScanner scannerWithString:string];
    unsigned int value = 0;
    [scanner scanHexInt:&value];
    if (length == 2) {
        *crc += value;
    } else
    if (length == 4) {
        *crc += (value >> 8);
        *crc += value & 0xff;
    }
    return value;
}

- (uint32_t)getHexProperty:(NSString *)key fallback:(uint32_t)fallback
{
    NSObject *object = [_properties valueForKey:key];
    if ([object isKindOfClass:[NSNumber class]]) {
        NSNumber *number = (NSNumber *)object;
        return [number intValue];
    }
    if (object) {
        NSScanner *scanner = [NSScanner scannerWithString:(NSString *)object];
        unsigned int value = 0;
        if ([scanner scanHexInt:&value]) {
            return value;
        }
    }
    return fallback;
}

#define FDIntelHexTypeDataRecord                   0
#define FDIntelHexTypeEndOfFileRecord              1
#define FDIntelHexTypeExtendedSegmentAddressRecord 2
#define FDIntelHexTypeStartSegmentAddressRecord    3
#define FDIntelHexTypeExtendedLinearAddressRecord  4
#define FDIntelHexTypeStartLinearAddressRecord     5

- (void)read:(NSString *)content address:(uint32_t)address length:(uint32_t)length
{
    _properties = [NSMutableDictionary dictionary];
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        if ([line hasPrefix:@"#! "]) {
            NSDictionary *dictionary = [FDJSON JSONObjectWithData:[[line substringFromIndex:2] dataUsingEncoding:NSUTF8StringEncoding]];
            [_properties addEntriesFromDictionary:dictionary];
        }
    }
    
    address = [self getHexProperty:@"address" fallback:address];
    length = [self getHexProperty:@"length" fallback:length];
    
    NSMutableData *firmware = [NSMutableData data];
    uint32_t extendedAddress = 0;
    bool done = false;
    for (NSString *line in lines) {
        if (![line hasPrefix:@":"]) {
            continue;
        }
        if (done) {
            continue;
        }
        int index = 1;
        uint8_t crc = 0;
        uint32_t byteCount = [FDIntelHex hex:line index:&index length:2 crc:&crc];
        uint32_t recordAddress = [FDIntelHex hex:line index:&index length:4 crc:&crc];
        uint32_t recordType = [FDIntelHex hex:line index:&index length:2 crc:&crc];
        NSMutableData *data = [NSMutableData data];
        for (int i = 0; i < byteCount; ++i) {
            uint8_t byte = [FDIntelHex hex:line index:&index length:2 crc:&crc];
            [data appendBytes:&byte length:1];
        }
        uint8_t ignore = 0;
        uint8_t checksum = [FDIntelHex hex:line index:&index length:2 crc:&ignore];
        crc = 256 - crc;
        if (checksum != crc) {
            @throw [NSException exceptionWithName:@"checksum mismatch" reason:@"checksum mismatch" userInfo:nil];
        }
        switch (recordType) {
            case FDIntelHexTypeDataRecord: {
                uint32_t targetAddress = extendedAddress + recordAddress;
                if (targetAddress >= address) {
                    uint32_t dataAddress = targetAddress - address;
                    uint32_t length = dataAddress + (uint32_t)data.length;
                    if (length > firmware.length) {
                        firmware.length = length;
                    }
                    uint8_t *bytes = (uint8_t *)firmware.bytes;
                    memcpy(&bytes[dataAddress], data.bytes, data.length);
                }
            } break;
            case FDIntelHexTypeEndOfFileRecord: {
                done = true;
            } break;
            case FDIntelHexTypeExtendedSegmentAddressRecord: {
                uint8_t *bytes = (uint8_t *)data.bytes;
                extendedAddress = ((bytes[0] << 8) | bytes[1]) << 4;
            } break;
            case FDIntelHexTypeStartSegmentAddressRecord: {
                // ignore
            } break;
            case FDIntelHexTypeExtendedLinearAddressRecord: {
                uint8_t *bytes = (uint8_t *)data.bytes;
                extendedAddress = (bytes[0] << 24) | (bytes[1] << 16);
            } break;
            case FDIntelHexTypeStartLinearAddressRecord: {
                // ignore
            } break;
        }
    }
    _data = firmware;
}

+ (void)addRecord:(NSMutableString *)content address:(uint32_t)address type:(uint8_t)type data:(NSData *)data
{
    uint8_t count = data.length;
    uint8_t checksum = count;
    uint8_t ah = address >> 8;
    checksum += ah;
    uint8_t al = address;
    checksum += al;
    checksum += type;
    [content appendFormat:@":%02x%02x%02x%02x", count, ah, al, type];
    uint8_t *bytes = (uint8_t *)data.bytes;
    for (NSUInteger i = 0; i < data.length; ++i) {
        uint8_t byte = bytes[i];
        [content appendFormat:@"%02x", byte];
        checksum += byte;
    }
    checksum = ~checksum + 1;
    [content appendFormat:@"%02x\n", checksum];
}

+ (void)addDataRecords:(NSMutableString *)content address:(uint32_t)address data:(NSData *)data addressHighWord:(uint32_t *)addressHighWord
{
    for (NSUInteger i = 0; i < data.length; i += 16) {
        if ((address & ~0xffff) != *addressHighWord) {
            uint8_t addressBytes[] = {address >> 24, address >> 16};
            [self addRecord:content address:0 type:FDIntelHexTypeExtendedLinearAddressRecord data:[NSData dataWithBytes:addressBytes length:sizeof(addressBytes)]];
            *addressHighWord = address & ~0xffff;
        }
        NSUInteger length = data.length - i;
        if (length > 16) {
            length = 16;
        }
        NSData *subdata = [data subdataWithRange:NSMakeRange(i, length)];
        [self addRecord:content address:address & 0xffff type:FDIntelHexTypeDataRecord data:subdata];
        address += 16;
    }
}

- (NSString *)format:(NSArray *)chunks comment:(BOOL)comment
{
    NSMutableString *content = [NSMutableString string];
    
    if (comment) {
        [content appendFormat:@"#! %@\n", [[NSString alloc] initWithData:[FDJSONSerializer serialize:self.properties] encoding:NSUTF8StringEncoding]];
    }
    
    uint32_t address = [self getHexProperty:@"address" fallback:0];
    uint32_t addressHighWord = 0;
    [FDIntelHex addDataRecords:content address:address data:self.data addressHighWord:&addressHighWord];
    for (FDIntelHexChunk *chunk in chunks) {
        [FDIntelHex addDataRecords:content address:chunk.address data:chunk.data addressHighWord:&addressHighWord];
    }
    
    [FDIntelHex addRecord:content address:0 type:FDIntelHexTypeEndOfFileRecord data:[NSData data]];
    
    return content;
}

- (NSString *)format
{
    return [self format:[NSArray array] comment:YES];
}

@end
