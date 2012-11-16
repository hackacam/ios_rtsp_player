//
//  FfmpegWrapper.h
//  rtsp_ffmpeg_player
//
//  Created by J.C. Li on 11/2/12.
//  Copyright (c) 2012 J.C. Li. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AVFrameData : NSObject
@property (nonatomic, strong) NSMutableData *colorPlane0;
@property (nonatomic, strong) NSMutableData *colorPlane1;
@property (nonatomic, strong) NSMutableData *colorPlane2;
@property (nonatomic, strong) NSNumber      *lineSize0;
@property (nonatomic, strong) NSNumber      *lineSize1;
@property (nonatomic, strong) NSNumber      *lineSize2;
@property (nonatomic, strong) NSNumber      *width;
@property (nonatomic, strong) NSNumber      *height;
@property (nonatomic, strong) NSDate        *presentationTime;
@end

@interface FfmpegWrapper : NSObject

-(id) init;

//-(id) initWithOutputFormat: (NSString *) format;

-(int) openUrl: (NSString *) url;

-(int) startDecodingWithCallbackBlock: (void (^) (AVFrameData *frame)) frameCallbackBlock
                      waitForConsumer: (BOOL) wait
                   completionCallback: (void (^)()) completion;

-(void) stopDecode;

+(UIImage *) convertFrameDataToImage: (AVFrameData *) avFrameData;

@end
