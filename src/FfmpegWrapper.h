//
//  FfmpegWrapper.h
//  rtsp_ffmpeg_player
//
//  Created by J.C. Li on 11/2/12.
//  Copyright (c) 2012 J.C. Li. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FfmpegWrapper : NSObject

-(id) init;

//-(id) initWithOutputFormat: (NSString *) format;

-(int) connectRTSPServer: (NSString *) url;

-(int) startDecodingWithCallbackBlock: (void (^) (unsigned char * yData,
                                                  int    yLineSize,
                                                  unsigned char * uData,
                                                  int    uLineSize,
                                                  unsigned char * vData,
                                                  int    vLineSize,
                                                  unsigned long timestamp,
                                                  int width,
                                                  int height)) frameCallbackBlock
                   imageCallbackBlock: (void (^) (UIImage * image,
                                                  unsigned long timestamp)) imageCallbackBlock
                   completionCallback: (void (^)()) completion;

@property (nonatomic, strong) NSNumber * pauseDecode;

@end
