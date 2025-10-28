const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

// Trigger when a new command is written to Firebase
exports.sendCommandNotification = functions.database
  .ref('/commands/{deviceID}/{commandID}')
  .onCreate(async (snapshot, context) => {
    const deviceID = context.params.deviceID;
    const commandID = context.params.commandID;
    const commandData = snapshot.val();

    console.log(`New command for device ${deviceID}: ${commandData.command}`);

    try {
      // Get the FCM token for the target device
      const deviceSnapshot = await admin.database()
        .ref(`/devices/${deviceID}`)
        .once('value');

      const device = deviceSnapshot.val();

      if (!device || !device.fcmToken) {
        console.warn(`No FCM token found for device ${deviceID}`);
        return null;
      }

      const fcmToken = device.fcmToken;

      // Send high-priority alert notification
      const message = {
        token: fcmToken,
        notification: {
          title: 'SafeGuard Control',
          body: 'Parental control update'
        },
        data: {
          command: commandData.command,
          commandID: commandID,
          timestamp: String(commandData.timestamp),
          type: 'guardian_command'
        },
        apns: {
          headers: {
            'apns-priority': '10',  // Immediate delivery
            'apns-push-type': 'alert'
          },
          payload: {
            aps: {
              alert: {
                title: 'SafeGuard Control',
                body: 'Parental control update'
              },
              sound: 'default',
              badge: 1,
              'content-available': 1  // Wake app in background
            },
            // Include command data as custom keys for iOS background processing
            command: commandData.command,
            commandID: commandID,
            timestamp: String(commandData.timestamp),
            type: 'guardian_command'
          }
        }
      };

      // Send the notification
      const response = await admin.messaging().send(message);
      console.log(`Successfully sent notification: ${response}`);

      return null;
    } catch (error) {
      console.error('Error sending notification:', error);
      return null;
    }
  });
