//
//  WebViewController.m
//  rtsp_player
//
//  Created by J.C. Li on 11/18/12.
//  Copyright (c) 2012 J.C. Li. All rights reserved.
//

#import "WebViewController.h"

@interface WebViewController ()
@property (weak, nonatomic) IBOutlet UIWebView *theWebView;

@end

@implementation WebViewController
@synthesize configUrl = _configUrl;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
}

- (void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    NSURL *url = [NSURL URLWithString:self.configUrl];
    NSURLRequest *requestObj = [NSURLRequest requestWithURL:url];
    
    
    [self.theWebView loadRequest:requestObj];

}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
