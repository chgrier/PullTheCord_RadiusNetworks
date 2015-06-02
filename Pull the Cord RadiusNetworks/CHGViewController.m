//
//  CHGViewController.m
//  Pull the Cord RadiusNetworks
//
//  Created by Charles Grier on 2/18/15.
//  Copyright (c) 2015 Grier Mobile Development. All rights reserved.
//

#import "CHGViewController.h"
#import "CHGStation.h"
#import <CoreLocation/CLCircularRegion.h>


@import CoreLocation;
@interface CHGViewController () <CLLocationManagerDelegate, MKMapViewDelegate>

@property (strong, nonatomic) NSMutableArray *stations;
@property (strong, nonatomic) MKPolyline *mapPolyline;
@property (strong, nonatomic) MKCircle *stationCircle;

@property (weak, nonatomic) IBOutlet MKMapView *mapView;
@property (weak, nonatomic) IBOutlet UIButton *stationMessageButton;
@property (weak, nonatomic) IBOutlet UILabel *arrivalMessageLabel;

@property (strong, nonatomic) RPKManager *proximityKitManager;
@property (strong, nonatomic) RPKMap *stationsFromMap;


@property (strong, nonatomic) AVSpeechSynthesizer *speechSynthesizer;

@end

@implementation CHGViewController
{
    CHGStation *_sortString;
    CHGStation *_monitoredStation;
    RPKRegion *_newRegion;
    CLCircularRegion * _monitoredCHGRegion;
    NSArray *_sortArray;
}

- (void)viewDidLoad {
    [super viewDidLoad];

# warning add your ProximityKit.plist file to your target
    
    // create and start to sync the manager with Radius Networks Proximity Kit backend
    self.proximityKitManager = [RPKManager managerWithDelegate:self];
    [self.proximityKitManager start];
    
    NSLog(@"Region monitored: %@", self.proximityKitManager.kit.json);
        
    NSLog(@"Name of Proximity Kit: %@", self.proximityKitManager.kit.name);
    NSLog(@"Version: %@", [RPKManager getVersion]);
        
    // New for iOS 8 - Register the notifications
    UIUserNotificationType types = UIUserNotificationTypeBadge | UIUserNotificationTypeSound | UIUserNotificationTypeAlert;
    UIUserNotificationSettings *mySettings = [UIUserNotificationSettings settingsForTypes:types categories:nil];
    [[UIApplication sharedApplication] registerUserNotificationSettings:mySettings];
    
    // grey-out station label
    [self.stationMessageButton setEnabled:NO];
    
    // add location arrow and clear button to top
    self.navigationItem.leftBarButtonItem = [[MKUserTrackingBarButtonItem alloc] initWithMapView:self.mapView];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Clear Alerts" style:UIBarButtonItemStyleBordered target:self action:@selector(stopRegionMonitoring:clearRegions:)];
    
    // needed?  location manager for MapKit to work.  Maybe redundant since it is also called by RPKManager?
    self.locationManager = [[CLLocationManager alloc]init];
    self.locationManager.delegate = self;
    
    // Check for iOS 8 for location authorization. Without this guard the code will crash with "unknown selector" on iOS 7.
    if ([self.locationManager respondsToSelector:@selector(requestAlwaysAuthorization)]) {
        [self.locationManager requestAlwaysAuthorization];
        }
    
    [self.locationManager startUpdatingLocation];
        
    self.mapView.delegate = self; // ***make sure to set delegate for map***
    self.mapView.showsUserLocation = YES;
        
    // add station and line info when view loads
    [self loadStationData];
    
    // add overlays and annotations of stations and rendered lines
    [self.mapView addOverlay:self.mapPolyline];
    [self.mapView addAnnotations:self.stations];
    
    // center map on San Diego
    CLLocationCoordinate2D center = CLLocationCoordinate2DMake(32.6673224,-117.0856415);
    MKCoordinateSpan span = MKCoordinateSpanMake(0.2, 0.2); // one degree of latitude is 69 miles; longitude varies
    MKCoordinateRegion regionToDisplay = MKCoordinateRegionMake(center, span);
    [self.mapView setRegion:regionToDisplay animated:NO];
}
    
#pragma mark CLLocation Manager Delegate Methods - not needed with Radius wrapper
-(void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
        // NSLog(@"%@", [locations lastObject]);
}
    
- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
        NSLog(@"didFailWithError %@", error);
}

    // if location authorization not allowed, provide a way to get to notify user and change in Settings
- (void)requestAlwaysAuthorization {
    
    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
        
    // If the status is denied or only granted for when in use, display an alert
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse || status == kCLAuthorizationStatusDenied) {
        NSString *title = (status == kCLAuthorizationStatusDenied) ? @"Location services \nare turned off" : @"Background location is not enabled";
        NSString *message = @"To receive alerts, you must change the Location Services Settings to 'Always'";
            
            
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title
                                                                                 message:message
                                                                          preferredStyle:UIAlertControllerStyleAlert];
            
        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                NSLog(@"Alert Action: Cancel pressed");
            }];
            
        UIAlertAction *settings = [UIAlertAction actionWithTitle:@"Location Settings" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                NSURL *settingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
                [[UIApplication sharedApplication] openURL:settingsURL];
                
            }];
            
            [alertController addAction:cancel];
            [alertController addAction:settings];
            
            [self presentViewController:alertController animated:YES completion:nil];
            
    }
    
    // If the user has not enabled any location services, request background authorization.
    else if (status == kCLAuthorizationStatusNotDetermined) {
        [self.locationManager requestAlwaysAuthorization];
    }
}


- (void)loadStationData {

    // get station count to create polyline

    NSArray *stationData = self.proximityKitManager.kit.map.overlays;
    NSUInteger stationCount = stationData.count; // determines the number of stations for the array
    NSLog(@"Number of stations in array: %lu", (unsigned long)stationCount);
    
    // create a C-style array based on the station count size
    NSUInteger i = 0;
    CLLocationCoordinate2D *polylineCoords = malloc(sizeof(CLLocationCoordinate2D) *stationCount); // used malloc manually allocate memory for block of memory of size equal to the size of each element multiplied by the number of elements
    self.stations = [[NSMutableArray alloc]initWithCapacity:stationCount];
    
    // access json files from Proximity Kit (must have Proximity Kit plist in project)
    NSDictionary *json = self.proximityKitManager.kit.json;
    NSDictionary *dict = [json objectForKey:@"map"];
    NSMutableArray *stationInfo = [dict objectForKey:@"overlays"];
    
    //NSDictionary *proximityKitJson = [[self.proximityKitManager.kit.json objectForKey:@"map"]objectForKey:@"overlays"];
    
    
    //RPKRegion *selectedRegion = [[self.proximityKitManager.kit.json objectForKey:@"map"]objectForKey:@"overlays"];
    //NSLog(@"Selected REGION: %@", selectedRegion);
    
        //NSLog(@"JSON info: %@", stationInfo); // check format

    // create NSDictionary to hold json data then enumerate using fast enumertation
    for (NSDictionary *stationDictionary in stationInfo) {
    
        // create coordinate pairs then add to polyLineCoords array
        CLLocationDegrees latitude = [[[stationDictionary objectForKey:@"center"]objectAtIndex:0] floatValue];
        CLLocationDegrees longitude = [[[stationDictionary objectForKey:@"center"]objectAtIndex:1] floatValue];
        CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(latitude, longitude);
        polylineCoords[i] = coordinate;
        
        CHGStation *station = [[CHGStation alloc]init];
        station.title = [stationDictionary objectForKey:@"name"];
        station.identifier = [stationDictionary objectForKey:@"identifier"];
        station.attributes = [stationDictionary objectForKey:@"attributes"];
        station.subtitle = [station.attributes objectForKey:@"Line"];
        station.stationNumber = [station.attributes valueForKey:@"StationNumber"];
        station.coordinate = coordinate;
        station.radius = [[stationDictionary objectForKey:@"radius"] floatValue];
        [self.stations addObject:station];

        //NSLog(@"Attributes: %@", station.attributes );
        //NSLog(@"Subtitle: %@", station.subtitle );
        
        i++;
        
    }

    // create polyline using coordinates from above
    self.mapPolyline = [MKPolyline polylineWithCoordinates:polylineCoords count:stationCount];
    
    // make sure to free memory, but after for loop - ARC cannot free after using malloc
    free(polylineCoords);

        /* example of using block to enumerate array
         [stationInfo enumerateObjectsUsingBlock:^(id obj, NSUInteger index, BOOL *stop) {
        // Fetch Single Item
        // Here obj will return a dictionary
        NSLog(@"Station name : %@",[obj valueForKey:@"name"]);
         }];
         */
    
}
    
    
- (void)didReceiveMemoryWarning {
        
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


# pragma mark - Map Overlay Delegate
-(MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay {
    
    if ([overlay isKindOfClass:[MKPolyline class]]){
        MKPolylineRenderer *renderer = [[MKPolylineRenderer alloc]initWithPolyline:overlay];
        renderer.lineWidth = 3.0f;
        renderer.strokeColor = [UIColor blueColor];
        
        return renderer;
        }
        
    if ([overlay isKindOfClass:[MKCircle class]]){
        MKCircleRenderer *circleRenderer = [[MKCircleRenderer alloc]initWithCircle:overlay];
        circleRenderer.lineWidth = 4.0f;
        circleRenderer.strokeColor = [UIColor colorWithRed:0.7 green:0 blue:0 alpha:0.5];
        circleRenderer.fillColor = [UIColor colorWithRed:1.0 green:0 blue:0 alpha:0.1];
            
        return circleRenderer;
        }
        return nil;
}
    
# pragma mark - Annotation Delegate
- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation isKindOfClass:[CHGStation class]]) {
        static NSString *const kPinIdentifier = @"CHGStation";
        MKAnnotationView *view = (MKAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:kPinIdentifier];
            
        if (!view) {
            view = [[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:kPinIdentifier];
            view.annotation = annotation;
            view.canShowCallout = YES;
            //view.calloutOffset = CGPointMake(-5, 5);
                
            //view.pinColor = MKPinAnnotationColorRed;
            view.draggable = NO;
            UIImageView *myCustomImage = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"trolleyLogo.jpg"]];
            view.image = [UIImage imageNamed:@"busStop.png"];
            UIButton *button = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
                
            // Add a custom image to the left side of the callout.
            view.leftCalloutAccessoryView = myCustomImage;
            view.rightCalloutAccessoryView = button;
        
        } else {
            //view.rightCalloutAccessoryView = nil;
            // TODO - above line sometimes removes callout
        }
            
        return view;
            
        }
        return nil;
}
    
#pragma mark -- Annotation Callout Tapped Delegate
    // Handle to set monitoring for geofence when callout button is tapped
-(void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view calloutAccessoryControlTapped:(UIControl *)control {
    [self requestAlwaysAuthorization];
        
        CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
        if (status == kCLAuthorizationStatusAuthorizedWhenInUse || status == kCLAuthorizationStatusDenied) {
            return;
        } else {
            CHGStation *selectedStation = (CHGStation *)view.annotation;
            NSString *identifer = [self.proximityKitManager getRegionForIdentifier:selectedStation.identifier].name;
            RPKRegion *region = [self.proximityKitManager getRegionForIdentifier:selectedStation.identifier];
            NSLog(@"REGION: %@", region.name);
            NSLog(@"IDENTIFIER: %@", identifer);
            
            NSString *title = @"Set alert";
            NSString *message = [NSString stringWithFormat:@"Get notified when you are approaching the %@", selectedStation.title];
            
            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleActionSheet];
            
            UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                NSLog(@"Alert Action: Cancel pressed");
            }];
            
            UIAlertAction *setAlert = [UIAlertAction actionWithTitle:@"Set Alert" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                
                //[self.locationManager startUpdatingLocation];
                [self selectStationAndZoom:selectedStation];
                //[self monitorSelectedStation:selectedStation];
                //RPKRegion *newRegion = [[RPKRegion alloc]init];
                [self createRegion:selectedStation forRPKRegion:_newRegion];
                
            }];
            
            [alertController addAction:cancel];
            [alertController addAction:setAlert];
            
            [self presentViewController:alertController animated:YES completion:nil];
            
            UIPopoverPresentationController *popover = alertController.popoverPresentationController;
            if (popover)
            {
                popover.sourceView = view;
                popover.sourceRect = view.bounds;
                popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
            }

            /*
            // create an action sheet
             UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
             
             // add button on action sheet to set alert for selected station
             [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Set alert for this station"]
             style:UIAlertActionStyleDefault
             handler:^(UIAlertAction *action) {
             
             [self monitorSelectedStation:selectedStation];
             
             // remove radius circle if one already exists
             if (self.stationCircle) {
             [self.mapView removeOverlay:self.stationCircle];
             
             }
             self.stationCircle = [MKCircle circleWithCenterCoordinate:selectedStation.coordinate radius:[selectedStation.radius floatValue]];
             self.stationCircle.title = @"%@", [NSString stringWithFormat:@"%@", selectedStation.title];
             
             [self.mapView addOverlay:self.stationCircle];
             
             MKCoordinateSpan span = MKCoordinateSpanMake(0.02, 0.02); // one degree of latitude is 69 miles; longitude varies
             MKCoordinateRegion regionToDisplay = MKCoordinateRegionMake(self.stationCircle.coordinate, span);
             [self.mapView setRegion:regionToDisplay animated:YES];
             
             }]];
             
             
             [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
             style:UIAlertActionStyleCancel
             handler:nil]];
             
             
             [self presentViewController:sheet animated:YES completion:nil];
*/
        }
             
}
    
-(void)selectStationAndZoom:(CHGStation *)selectedStation {

    [self showAlertforRegionMonitoring:selectedStation];
    
    if (self.stationCircle) {
        [self.mapView removeOverlay:self.stationCircle];
    }
        
    self.stationCircle = [MKCircle circleWithCenterCoordinate:selectedStation.coordinate radius:selectedStation.radius];
    self.stationCircle.title = @"%@", [NSString stringWithFormat:@"%@", selectedStation.title];
        
    [self.mapView addOverlay:self.stationCircle];
    
    MKCoordinateSpan span = MKCoordinateSpanMake(0.025, 0.025); // one degree of latitude is 69 miles; longitude varies
    MKCoordinateRegion regionToDisplay = MKCoordinateRegionMake(self.stationCircle.coordinate, span);
    [self.mapView setRegion:regionToDisplay animated:YES];
    
    //[self.proximityKitManager sync];
    
    //[self.locationManager startMonitoringForRegion:[[CLCircularRegion alloc]initWithCenter:selectedStation.coordinate radius:selectedStation.radius identifier:selectedStation.title]];
    
}
    
// zoom to station with alert
- (IBAction)zoomToSelectedStation:(id)sender {
    MKCoordinateSpan span = MKCoordinateSpanMake(0.025, 0.025); // one degree of latitude is 69 miles; longitude varies
    MKCoordinateRegion regionToDisplay = MKCoordinateRegionMake(self.stationCircle.coordinate, span);
    [self.mapView setRegion:regionToDisplay animated:YES];
}
    
#pragma mark - Native Region Monitoring (Geofencing) Methods


// start monitoring for region
/*
-(void)monitorSelectedStation:(CHGStation *)station {

    for (CLRegion *region in [[self.locationManager monitoredRegions] allObjects]) {
            if (![region.identifier isEqualToString:station.title]) {
                
                [self.locationManager stopMonitoringForRegion:region];
            }
        }
        
    NSLog(@"ONE: # of Regions being monitored at beginning of method: %lu", (unsigned long)[self.locationManager monitoredRegions].count);
    NSLog(@"ONE: # of RadiusNetworkRegions being monitored at beginning of method: %lu", (unsigned long)[self.locationManager monitoredRegions].count);
        //[self.locationManager startUpdatingLocation];
    NSLog(@"TWO: # of Regions being monitored after calling stopMonitoringForRegion: %lu", (unsigned long)[self.locationManager monitoredRegions].count);
    
    [self.locationManager startMonitoringForRegion:[[CLCircularRegion alloc]initWithCenter:station.coordinate radius:station.radius identifier:station.title]];
        
    //TODO change radius variable from float to
    NSLog(@"THREE: # of Regions being monitored after calling startMonitoring: %lu", (unsigned long)[self.locationManager monitoredRegions].count);
    NSLog(@"STATION being monitored: %@", station.title);
        
    NSLog(@"REGION being monitored: %@", [self.locationManager monitoredRegions]);
        
    // notify user on interface which station is being monitored
    [self showAlertforRegionMonitoring:station];

    }
*/

// select region and create CLRegion

-(void)createRegion: (CHGStation *)station forRPKRegion: (RPKRegion *)rpkRegion {
    CLCircularRegion *monitoredRegion = [[CLCircularRegion alloc]initWithCenter:station.coordinate radius:station.radius identifier:station.identifier];
    
    _monitoredCHGRegion = monitoredRegion;

    //rpkRegion = (RPKRegion *)monitoredRegion;
    //RPKRegion *monitoredRPKRegion = (RPKRegion *)monitoredRegion;
    //NSLog(@"*******RPKREgion being monitored: %@", monitoredRPKRegion.identifier);
    
    
    
    }




    
// alert view for region monitoring

-(void)showAlertforRegionMonitoring:(CHGStation *)station {

        
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Alert set!"
                                                    message:[NSString stringWithFormat:@"You will be notified when approaching %@", station.title]
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];
        
        // [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification* notification){
        //     [alert ];
        //}];
    }
    
    // delegates for region monitoring





/*
-(void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region {
        
    self.arrivalMessageLabel.text = @"Arriving at:";
    //self.stationMessageButton.titleLabel.text = [NSString stringWithFormat:@"%@", region.identifier];
    [self.stationMessageButton setTitle:[NSString stringWithFormat:@"%@", region.identifier] forState:UIControlStateNormal];
        
    [self didEnterRegionAlert:region];
    [self.locationManager stopMonitoringForRegion:region];
    [self.locationManager stopUpdatingLocation];
        
        
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Arriving at your station"
                                                    message:[NSString stringWithFormat:@"You are approaching %@", region.identifier]
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];
         
         
    NSLog(@"You just entered geofence %@",region.identifier);
    self.arrivalMessageLabel.text = @"Arriving at:";
    //self.stationMessageLabel.text = [NSString stringWithFormat:@"%@", region.identifier];
         
    self.speechSynthesizer = [[AVSpeechSynthesizer alloc]init];
    static AVSpeechUtterance *utterance;
         
    NSString *stationTalk = [NSString stringWithFormat:@"Arriving at: %@.", region.identifier];
    utterance = [[AVSpeechUtterance alloc]initWithString:stationTalk];
    utterance.rate = 0.2f;
    utterance.volume = 1.0f;
    utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"];
         
    [self.speechSynthesizer speakUtterance:utterance];
        
}
*/

/*
-(void)didEnterRegionAlert:(CLRegion *)region {
        
        
    UILocalNotification *notification = [[UILocalNotification alloc] init];
    notification.alertBody = [NSString stringWithFormat:@"Arriving at %@", region.identifier];
    notification.soundName = @"School Bell Ringing.caf";
    [[UIApplication sharedApplication] presentLocalNotificationNow:notification];
        
        
    NSString *title = @"Arriving at your station";
    NSString *message = [NSString stringWithFormat:@"You are approaching %@", region.identifier];
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        
    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK"
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
                                                       
                        NSLog(@"Alert Action: OK pressed");
                        //[self.locationManager stopMonitoringForRegion:region];
                        NSLog(@"Regions being currently monitored: %@", [self.locationManager monitoredRegions]);
                                                       
                        }];
        
    NSLog(@"You just entered geofence %@",region.identifier);
    [alertController addAction:ok];
        
    [self presentViewController:alertController animated:YES completion:nil];
        
    self.speechSynthesizer = [[AVSpeechSynthesizer alloc]init];
    static AVSpeechUtterance *utterance;
    NSString *stationTalk = [NSString stringWithFormat:@"Arriving at: %@.", region.identifier];
    utterance = [[AVSpeechUtterance alloc]initWithString:stationTalk];
    utterance.rate = 0.2f;
    utterance.volume = 1.0f;
    utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"];
        
    [self.speechSynthesizer speakUtterance:utterance];
    
}
*/

/*
-(void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region {
    [self.locationManager stopMonitoringForRegion:region];
    self.arrivalMessageLabel.text = @"No alert set";
    [self.stationMessageButton setTitle:[NSString stringWithFormat:@"%@", region.identifier] forState:UIControlStateNormal];
}
*/

/*
-(void)locationManager:(CLLocationManager *)manager didStartMonitoringForRegion:(CLRegion *)region {
        
# warning - May delete all monitored regions
        // ***check to see if this works - make sure it doesn't clear everything
        
    if ([self.locationManager monitoredRegions].count > 1) {
        //[self.locationManager stopMonitoringForRegion:[[[self.locationManager monitoredRegions] allObjects] objectAtIndex:0]];
        [self.locationManager stopMonitoringForRegion:region];
        NSLog(@"More than one region detected: Now monitoring for %@", region.identifier);
    }
    
    if ([self.locationManager monitoredRegions]) {
        [self.locationManager stopMonitoringForRegion:region];
         NSLog(@"Now monitoring for %@ with radius of %f meters", region.identifier, region.radius);
        }
         
       
    self.arrivalMessageLabel.text = @"Alert set for:";
        
    [self.stationMessageButton setEnabled:YES];
    [self.stationMessageButton setTitle:[NSString stringWithFormat:@"%@", region.identifier] forState:UIControlStateNormal];
    self.stationMessageButton.titleLabel.textColor = [UIColor redColor];
        
    // have to request state if already in region when app starts monitoring
    [self.locationManager requestStateForRegion:region];
    //[self locationManager:manager didEnterRegion:region];
    NSLog(@"Regions being currently monitored after setting alert: %@", [self.locationManager monitoredRegions]);
}
*/

/*
- (void) locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(CLRegion *)region withError:(NSError *)error {
        NSLog (@"Error: %@", [error localizedDescription]);
        NSLog(@"*****Could not monitor: %@", region.identifier);
}
*/

/*
- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region {
        
    if (state == CLRegionStateInside){
        NSLog(@"is in target region");
        [self locationManager:manager didEnterRegion:region];
            
        } else {
        NSLog(@"is out of target region");
        }
}
 

*/

/*
-(void)locationManager:(CLLocationManager *)manager didStartMonitoringForRegion:(CLRegion *)region{
    RPKRegion *newRegion = (RPKRegion *)region;
    NSLog(@"newRegion %@", newRegion);
}
 */

- (void)proximityKit:(RPKManager *)manager didDetermineState:(RPKRegionState)state forRegion:(RPKRegion *)region {
   
    
    if ([_monitoredStation.identifier isEqualToString:region.identifier]) {
        
        [manager getRegionForIdentifier:region.identifier];
        
        NSLog(@"Region from method call: %@", region.identifier);
        
    NSLog(@"**************State******: %@", region.identifier);
  
        
         NSLog(@"----------RPKREgion being monitored:----------- %@", region.name);
        if (state == RPKRegionStateInside) {
            NSLog(@"######is in target region %@", region.name);
            [self proximityKit:manager didEnter:region];
        }
    
        if (state == RPKRegionStateOutside) {
            NSLog(@"*******is out of target region %@", region.name);
        
    }
        }
}



- (void)stopRegionMonitoring:(id)sender clearRegions:(CLRegion *)region {
        
    [self.stationMessageButton setEnabled:NO];
    [self.stationMessageButton setTitle:@"Select station on map" forState:UIControlStateNormal];
        
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Clear alerts?" message:@"Press OK to clear alerts" preferredStyle:UIAlertControllerStyleAlert];
        
    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK"
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
                                                       
                                            //[self.locationManager stopMonitoringForRegion:region];
                                            //[self.locationManager stopUpdatingLocation];
                                                       
                                            if (self.stationCircle) {
                                                [self.mapView removeOverlay:self.stationCircle];
                                            }
                                                       
                                            self.arrivalMessageLabel.text = @"No alert set";
                                            self.stationMessageButton.titleLabel.text = @"Select station on map";
                                                       
                                            for (id currentAnnotation in self.mapView.annotations) {
                                                if ([currentAnnotation isKindOfClass:[CHGStation class]]) {
                                                    [self.mapView deselectAnnotation:currentAnnotation animated:YES];
                                                }
                                            }
                                            }];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel"
                                                     style:UIAlertActionStyleCancel
                                                   handler:^(UIAlertAction *action) {
                                                           return;
                                                   }];
        
    [alertController addAction:cancel];
    [alertController addAction:ok];
        
        
    [self presentViewController:alertController animated:YES completion:nil];
    
    //[self.proximityKitManager stop];
        
        
        
    //NSLog(@"Regions being currently monitored after PRESSING CLEAR: %@", [self.locationManager monitoredRegions]);
}
    
/*
- (void)mapView:(MKMapView *)mapView didUpdateUserLocation:(MKUserLocation *)userLocation {
    if (_foundLocationCallback) {
        _foundLocationCallback(userLocation.coordinate);
    }
    _foundLocationCallback = nil;
}
    
- (void)performAfterFindingLocation:(CHGLocationCallback)callback {
    if (self.mapView.userLocation != nil) {
        if (callback) {
            callback(self.mapView.userLocation.coordinate);
    }
    } else {
            _foundLocationCallback = [callback copy];
    }
}
    
*/
#pragma mark ProximityKit delegate methods

- (void)proximityKit:(RPKManager *)manager didEnter:(RPKRegion *)region {
    
    if ([region.name isEqualToString:_monitoredStation.name])
    //RPKRegion *rpkRegion = (RPKRegion *)_monitoredCHGRegion;
    NSLog(@"ENTERED: %@ MONITORED REGION %@", region.name, _monitoredCHGRegion.identifier);
    
    if (region) {
    
        UILocalNotification *notification = [[UILocalNotification alloc] init];
        notification.alertBody = [NSString stringWithFormat:@"Arriving at %@", region.identifier];
        //notification.soundName = @"School Bell Ringing.caf";
        [[UIApplication sharedApplication] presentLocalNotificationNow:notification];
        
        NSString *title = @"Arriving at your station";
        NSString *message = [NSString stringWithFormat:@"You are approaching %@", region.name];
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK"
                                                     style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction *action) {
                                                       
                                                       NSLog(@"Alert Action: OK pressed");
                                                       //[self.locationManager stopMonitoringForRegion:region];
                                                   }];
        
        [alertController addAction:ok];
        
        [self presentViewController:alertController animated:YES completion:nil];
        
        self.speechSynthesizer = [[AVSpeechSynthesizer alloc]init];
        static AVSpeechUtterance *utterance;
        NSString *stationTalk = [NSString stringWithFormat:@"Arriving at: %@.", region.name];
        utterance = [[AVSpeechUtterance alloc]initWithString:stationTalk];
        utterance.rate = 0.2f;
        utterance.volume = 1.0f;
        utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"];
        
        [self.speechSynthesizer speakUtterance:utterance];
    
     }
   
}

- (void)proximityKit:(RPKManager *)manager didExit:(RPKRegion *)region {
    NSLog(@"exited %@", region);
}



@end
