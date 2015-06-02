# Pull the Cord! 
###Transit Alerts using Radius Networks' Proximity Kit SDK
######Description:
An iOS app that uses the Radius Networks SDK to create geofencing alerts when the user's selected transit stop is approaching.

The app uses native Radius Networks' region monitoring using the Proximity Kit SDK to monitor when the user enters a selected region.  Regions were manually created using the Proximity Kit developer portal. 

##### In order for the app to work, one must create an a Proximity Kit at https://proximitykit.radiusnetworks.com and add the config plist to the project.

######Features: 

- Uses RPKManager to access the JSON data from the Proximity Kit SDK.
- MapKit for mapping routes and stations.
    - MKOverlayRenderer for mapping transit lines.
    - MKAnnotationView for map callouts and annotations.
- AVFoundation to create audible alerts.
    - AVSpeechSynthesizer to produce synthesized speech to alert the user of their upcoming station.
- UILocalNotification provides nofications when app is running in the background.
- NSJSONSerialization to convert JSON-formatted station to Foundation objects for mapping.
