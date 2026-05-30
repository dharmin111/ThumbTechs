const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();

/**
 * FUNCTION 1
 * Register FCM Token
 */
exports.registerFCMToken = functions.https.onRequest(
    async (req, res) => {
      res.set("Access-Control-Allow-Origin", "*");
      res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      res.set("Access-Control-Allow-Headers", "Content-Type");

      if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
      }

      if (req.method !== "POST") {
        res.status(405).json({
          success: false,
          error: "Method not allowed",
        });
        return;
      }

      try {
        const {
          userId,
          fcmToken,
          userType,
        } = req.body;

        if (!userId || !fcmToken || !userType) {
          res.status(400).json({
            success: false,
            error: "Missing required fields",
            required: [
              "userId",
              "fcmToken",
              "userType",
            ],
          });
          return;
        }

        const collection =
          userType === "technician" ?
            "technicians" :
            "users";

        await db.collection(collection).doc(userId).set({
          fcmToken: fcmToken,
          userType: userType,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});

        functions.logger.info(
            `FCM token registered for ${userType}: ${userId}`,
        );

        res.status(200).json({
          success: true,
          message: "FCM token registered successfully",
        });
      } catch (error) {
        functions.logger.error(
            "registerFCMToken error:",
            error,
        );

        res.status(500).json({
          success: false,
          error: error.message,
        });
      }
    },
);

/**
 * FUNCTION 2
 * Notify Technicians On New Task
 */
exports.notifyTechniciansOnNewTask = functions.firestore
    .document("tasks/{taskId}")
    .onCreate(async (snap, context) => {
      try {
        const taskData = snap.data();
        const taskId = context.params.taskId;

        const {
          category,
          pincode,
          customerName,
        } = taskData;

        if (!category || !pincode) {
          functions.logger.warn(
              `Task ${taskId} missing category/pincode`,
          );

          return null;
        }

        const techniciansSnapshot = await db
            .collection("technicians")
            .where("category", "==", category)
            .where("pincode", "==", pincode)
            .get();

        if (techniciansSnapshot.empty) {
          functions.logger.info(
              "No technicians found",
          );

          return null;
        }

        const tokens = [];

        techniciansSnapshot.forEach((doc) => {
          const token = doc.data().fcmToken;

          if (token && token.trim() !== "") {
            tokens.push(token);
          }
        });

        if (tokens.length === 0) {
          functions.logger.warn(
              "No valid FCM tokens available",
          );

          return null;
        }

        const message = {
          notification: {
            title: "🔧 New Task Available",
            body:
            `${customerName || "Customer"} ` +
            `needs ${category} service`,
          },

          data: {
            type: "task_assigned",
            taskId: taskId,
            category: category,
            pincode: pincode,
            timestamp: Date.now().toString(),
          },

          tokens: tokens,
        };

        const response = await admin
            .messaging()
            .sendEachForMulticast(message);

        functions.logger.info(
            `Notifications sent: ${response.successCount}`,
        );

        return null;
      } catch (error) {
        functions.logger.error(
            "notifyTechniciansOnNewTask error:",
            error,
        );

        return null;
      }
    });

/**
 * FUNCTION 3
 * Send Chat Notification
 */
exports.sendChatNotification = functions.firestore
    .document("chats/{chatId}/messages/{messageId}")
    .onCreate(async (snap, context) => {
      try {
        const messageData = snap.data();

        const {
          senderId,
          recipientId,
          text,
        } = messageData;

        const chatId = context.params.chatId;

        if (!recipientId || !text) {
          return null;
        }

        if (senderId === recipientId) {
          return null;
        }

        let recipientDoc = await db
            .collection("users")
            .doc(recipientId)
            .get();

        if (!recipientDoc.exists) {
          recipientDoc = await db
              .collection("technicians")
              .doc(recipientId)
              .get();
        }

        if (!recipientDoc.exists) {
          functions.logger.warn(
              `Recipient not found: ${recipientId}`,
          );

          return null;
        }

        const recipientToken =
        recipientDoc.data().fcmToken;

        if (!recipientToken) {
          functions.logger.warn(
              "Recipient has no FCM token",
          );

          return null;
        }

        let senderName = "Someone";

        let senderDoc = await db
            .collection("users")
            .doc(senderId)
            .get();

        if (!senderDoc.exists) {
          senderDoc = await db
              .collection("technicians")
              .doc(senderId)
              .get();

          if (senderDoc.exists) {
            senderName =
            senderDoc.data().name ||
            "Technician";
          }
        } else {
          senderName =
          senderDoc.data().name ||
          "Customer";
        }

        const previewText =
        text.length > 60 ?
          `${text.substring(0, 60)}...` :
          text;

        const message = {
          notification: {
            title:
            `💬 Message from ${senderName}`,
            body: previewText,
          },

          data: {
            type: "new_message",
            chatId: chatId,
            senderId: senderId,
            recipientId: recipientId,
            message: text,
            timestamp: Date.now().toString(),
          },

          token: recipientToken,
        };

        await admin.messaging().send(message);

        functions.logger.info(
            `Chat notification sent to ${recipientId}`,
        );

        return null;
      } catch (error) {
        functions.logger.error(
            "sendChatNotification error:",
            error,
        );

        return null;
      }
    });

/**
 * FUNCTION 4
 * Health Check
 */
exports.healthCheck = functions.https.onRequest(
    async (req, res) => {
      try {
        res.status(200).json({
          success: true,
          status: "healthy",
          timestamp: new Date().toISOString(),
          runtime: "Node.js 18",
          version: "1st Gen",
          functions: [
            "registerFCMToken",
            "notifyTechniciansOnNewTask",
            "sendChatNotification",
            "healthCheck",
          ],
        });
      } catch (error) {
        res.status(500).json({
          success: false,
          error: error.message,
        });
      }
    },
);

console.log(
    "✅ Thumbtech Cloud Functions loaded successfully",
);