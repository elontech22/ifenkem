import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import * as functions from "firebase-functions/v2/firestore";

initializeApp();
const db = getFirestore();
const messaging = getMessaging();



// ----------------- Chat Notifications (fixed + logging) -----------------
export const sendChatNotification = functions.onDocumentCreated(
    "chats/{chatId}/messages/{messageId}",
    async (event) => {
        const msg = event.data;
        console.log("sendChatNotification triggered, msg:", msg);
        if (!msg) {
            console.error("No message data.");
            return null;
        }

        // possible field names for receiver (make robust)
        const receiverId = msg.receiverId || msg.to || msg.toId || null;
        if (!receiverId) {
            console.error("Missing receiverId in message document. messageId:", event.params.messageId);
            return null;
        }

        // get receiver doc and token
        const receiverDoc = await db.collection("users").doc(receiverId).get();
        if (!receiverDoc.exists) {
            console.error("Receiver doc not found:", receiverId);
            return null;
        }

        const fcmToken = receiverDoc.data()?.fcmToken;
        if (!fcmToken || typeof fcmToken !== "string" || fcmToken.trim() === "") {
            console.error("No valid fcmToken for receiver:", receiverId, "token:", fcmToken);
            return null;
        }

        // sender display name
        const senderDoc = await db.collection("users").doc(msg.senderId).get();
        const senderName = senderDoc.exists ? (senderDoc.data()?.name || "Someone") : "Someone";

        const messagePayload = {
            token: fcmToken,
            notification: {
                title: `Message from ${senderName}`,
                body: msg.text || "New message",
            },
            data: {
                type: "chat_message",
                senderId: msg.senderId || "",
                senderName,
                message: msg.text || "",
            },
            android: {
                priority: "high",
                notification: {
                    channelId: "chat_channel",
                },
            },
        };

        try {
            const resp = await messaging.send(messagePayload);
            console.log("Chat notification sent:", resp, "to token:", fcmToken);
            return resp;
        } catch (err) {
            console.error("Failed to send chat notification:", err);
            throw err;
        }
    }
);


// ----------------- Chat Notifications original old -----------------
// export const sendChatNotification = functions.onDocumentCreated(
//     "chats/{chatId}/messages/{messageId}",
//     async (event) => {
//         const msg = event.data;
//         if (!msg) return null;

//         const senderDoc = await db.collection("users").doc(msg.senderId).get();
//         const senderName = senderDoc.exists ? senderDoc.data()?.name || "Someone" : "Someone";

//         const receiverDoc = await db.collection("users").doc(msg.receiverId).get();
//         const fcmToken = receiverDoc.exists ? receiverDoc.data()?.fcmToken : null;
//         if (!fcmToken) return null;

//         const payload = {
//             notification: {
//                 title: `Message from ${senderName}`,
//                 body: msg.text || "New message",
//             },
//             data: {
//                 type: "chat_message",
//                 senderId: msg.senderId,
//                 senderName,
//                 message: msg.text || "",
//             },
//             token: fcmToken,
//         };

//         return messaging.send(payload);
//     }
// );

// ----------------- Like Notifications -----------------
export const sendLikeNotification = functions.onDocumentCreated(
    "likes/{targetUid}/received/{senderUid}",
    async (event) => {
        const targetUid = event.params.targetUid;
        const senderUid = event.params.senderUid;

        const likerDoc = await db.collection("users").doc(senderUid).get();
        const likerName = likerDoc.exists ? likerDoc.data()?.name || "Someone" : "Someone";

        const likedUserDoc = await db.collection("users").doc(targetUid).get();
        const fcmToken = likedUserDoc.exists ? likedUserDoc.data()?.fcmToken : null;
        if (!fcmToken) return null;

        const payload = {
            notification: {
                title: "New Like ❤️",
                body: `${likerName} liked your profile!`,
            },
            data: {
                type: "like_notification",
                likerId: senderUid,
                likerName,
            },

            token: fcmToken,
        };

        return messaging.send(payload);
    }
);

// ----------------- Update Notifications (fixed + logging) -----------------
export const sendUpdateNotification = functions.onDocumentCreated(
    "updates/{updateId}",
    async (event) => {
        const update = event.data;
        console.log("sendUpdateNotification triggered, update:", update);
        if (!update) {
            console.error("No update data.");
            return null;
        }

        const usersSnapshot = await db.collection("users").get();
        const tokens = usersSnapshot.docs
            .map((u) => u.data()?.fcmToken)
            .filter((t) => typeof t === "string" && t && t.trim().length > 0);

        if (!tokens || tokens.length === 0) {
            console.error("No FCM tokens found for update notification.");
            return null;
        }

        const multicastMessage = {
            tokens,
            data: {
                type: "update_notification",
                body: update.message || "A new version is ready on Play Store!",
            },
        };

        try {
            const resp = await messaging.sendMulticast(multicastMessage);
            console.log("sendUpdateNotification result:", resp);
            return resp;
        } catch (err) {
            console.error("Failed to send update notification:", err);
            throw err;
        }
    }
);



// // ----------------- Update Notifications original old -----------------
// export const sendUpdateNotification = functions.onDocumentCreated(
//     "updates/{updateId}",
//     async (event) => {
//         const update = event.data;
//         if (!update) return null;

//         const usersSnapshot = await db.collection("users").get();
//         const tokens = usersSnapshot.docs
//             .map((u) => u.data()?.fcmToken)
//             .filter(Boolean);

//         if (tokens.length === 0) return null;

//         const payload = {
//             notification: {
//                 title: "Update Available 🚀",
//                 body: update.message || "A new version is ready on Play Store!",
//             },
//             data: { type: "update_notification" },
//         };

//         return messaging.sendMulticast({ tokens, ...payload });
//     }
// );
