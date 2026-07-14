# Goal

Build an executable flutter application that helps users managing personal or shared passwords

## Phase 1

For the first phase, our target is to make sure the application works on Android phones. iOS can be ignore for now in terms of testing. The implementation should still consider iOS in the future.

# Requirements

1. Users can save account information (user id and password) in the app.
2. Users can generate passwords with options to accomondate typical password requirements for differen websites or applications.
3. Users can edit/delete any stored account information in the app.
4. Users can only view stored account information belong to the signed-in user account.
5. The app should required users to sign-in before using the application.
6. The app should allow biometric option besides user id and password.
7. The app should required users to register the signed-in device for future public/private key encryption purposes.
8. The app should only send encrypted inforamtion via HTTP (RESTful) requests.
9. Users should have the ability to delete their own accounts. Upon account deletion, all stored information associated with the deleted account should be hard deleted from the backend.
10. The app should have the ability to run as background service(s) on the phone, so that users using other applications can easily utilize this application features to fetch/store account information for the applications users are trying to use.
