//
//  ViewController.m
//  rtsp_player
//
//  Created by J.C. Li on 11/15/12.
//  Copyright (c) 2012 J.C. Li. All rights reserved.
//

#import "RootViewController.h"
#import "FfmpegWrapper.h"

@interface RootViewController (){
    int _counter;
}
@property (nonatomic, strong) FfmpegWrapper *h264dec;

@end

@implementation RootViewController
@synthesize h264dec=_h264dec;

-(FfmpegWrapper *) h264dec
{
    if (!_h264dec){
        _h264dec = [[FfmpegWrapper alloc] init];
    }
    return _h264dec;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.

    _counter=0;
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *sampleUrl = [mainBundle pathForResource:@"itu" ofType:@"h264"];
    int status = [self.h264dec openUrl:sampleUrl];
    if (status==0){
        [self.h264dec startDecodingWithCallbackBlock:^(AVFrameData *frame) {
            _counter++;
            if (_counter<5){
//                UIImage *outputImage = [FfmpegWrapper convertFrameDataToImage:frame];
//                NSData *imgData = UIImagePNGRepresentation(outputImage); // convert to png
                NSMutableData *yuvData = [[NSMutableData alloc] initWithData:frame.colorPlane0];
                [yuvData appendData:frame.colorPlane1];
                [yuvData appendData:frame.colorPlane2];
                NSString *pngPath = [NSHomeDirectory() stringByAppendingFormat:@"/Documents/testOutput%dx%d_yuv420_%d.yuv",
                                     frame.width.intValue, frame.height.intValue, _counter]; // identity
                NSLog(@"%@", pngPath);
//                [imgData writeToFile:pngPath atomically:YES];
 
                if (![yuvData writeToFile:pngPath atomically:YES]){
                    NSLog(@"write failed!");
                }
            }
            NSLog(@"width = %@", frame.width);
        } waitForConsumer:YES completionCallback:^{
            
        }];
    }
    
    usleep(1000000);
    [self.h264dec stopDecode];
    self.h264dec = nil;
    
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
