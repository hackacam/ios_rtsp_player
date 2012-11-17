//
//  FfmpegWrapperTest.m
//  rtsp_player
//
//  Created by J.C. Li on 11/15/12.
//  Copyright (c) 2012 J.C. Li. All rights reserved.
//

#import "FfmpegWrapperTest.h"
#import "FfmpegWrapper.h"
#include <libkern/OSAtomic.h>

@implementation FfmpegWrapperTest

- (void)setUp
{
    [super setUp];
    
    // Set-up code here.
}

- (void)tearDown
{
    // Tear-down code here.
    
    [super tearDown];
}

- (void)testFfmpegWrapperFileDecode
{
    FfmpegWrapper * h264dec = [[FfmpegWrapper alloc] init];
    NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
    
    NSMutableArray *referenFrameArray = [[NSMutableArray alloc] init];
    // load reference output data
    for (int i=0; i<4; i++){
        NSString *resourcePath = [NSString stringWithFormat:@"testOutput720x480_yuv420_%d", i+1];
        NSString *referenceFramePath = [testBundle pathForResource:resourcePath ofType:@"yuv"];
        NSData *frameData = [NSData dataWithContentsOfFile:referenceFramePath];
        STAssertNotNil(frameData, @"failed to open reference data %@", resourcePath);
        [referenFrameArray addObject:frameData];
    }
    
    // open the test file
    NSString *sampleUrl = [testBundle pathForResource:@"itur525_26kielharbour4_original_720x480_-avg-bps_2000000" ofType:@"h264"];
    int status = [h264dec openUrl:sampleUrl];
    STAssertEquals(status, 0, @"input sample file open failed");
    
    volatile __block int counter=0;

    [h264dec startDecodingWithCallbackBlock:^(AVFrameData *frame) {
        OSMemoryBarrier();
        if (counter<4){
            NSMutableData *tempData = [[NSMutableData alloc] init];
            [tempData appendData:frame.colorPlane0];
            [tempData appendData:frame.colorPlane1];
            [tempData appendData:frame.colorPlane2];
            STAssertTrue(tempData.length == [[referenFrameArray objectAtIndex:counter] length], @"frame data length mismatch");
            for (int i=0; i<tempData.length; i++){
                STAssertTrue(((unsigned char *)(tempData.bytes))[i] == ((unsigned char *)([[referenFrameArray objectAtIndex:counter] bytes]))[i], @"frame data mismatch for test frame %d at sample %d", counter, i);
                break;
            }
            OSMemoryBarrier();
            counter++;
        }
    } waitForConsumer:YES completionCallback:^{
        NSLog(@"decode complete.");
    }];
    
    sleep(1);
    [h264dec stopDecode];
    sleep(1);
}

@end
