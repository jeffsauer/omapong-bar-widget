/*
 * main.qml
 *
 * Single-player Pong-style game in Qt QML.
 *
 * Controls:
 *   W / S or Up / Down: move left paddle
 *   R / Space / Enter: restart after game over
 *
 * This version uses unversioned imports for Qt 6.
 * For Qt 5.15, change the first two imports to:
 *
 * import QtQuick 2.15
 * import QtQuick.Window 2.15
 */

import QtQuick
import QtQuick.Window

Window {
    id: gameWindow
    visible: true
    width: 900
    height: 600
    minimumWidth: 680
    minimumHeight: 420
    title: "Pong"
    color: "#0d1015"

    property int playerScore: 0
    property int aiScore: 0
    property int totalScore: playerScore + aiScore
    property int rallyCount: 0
    property bool gameOver: false

    property bool upPressed: false
    property bool downPressed: false

    onActiveChanged: {
        if (!active) {
            upPressed = false;
            downPressed = false;
        }
    }

    // Game field and object sizes
    property int margin: 30
    property int paddleWidth: 14
    property int paddleHeight: 100
    property int ballRadius: 10
    property int winScore: 7

    // Difficulty tuning constants.
    // Increase these for a harder game, decrease for an easier game.
    property real baseBallSpeed: 6.0
    property real maxBallSpeed: 14.5
    property real basePlayerSpeed: 7.5
    property real baseAISpeed: 4.5

    // Ball position and velocity, in field coordinates.
    property real ballX: 450
    property real ballY: 300
    property real ballVelX: 0.0
    property real ballVelY: 0.0

    // ---------------------------------------------------------------------
    // Visual layout
    // ---------------------------------------------------------------------

    Rectangle {
        id: field
        x: margin
        y: margin
        width: gameWindow.width - 2 * margin
        height: gameWindow.height - 2 * margin
        color: "#12171f"
        border.color: "#2b313c"
        border.width: 2
        clip: true

        Rectangle {
            id: centerLine
            x: field.width / 2 - 1
            width: 2
            height: field.height
            color: "#353c48"
        }

        Text {
            text: playerScore
            color: "#57c7ff"
            font.pixelSize: 46
            font.bold: true
            x: field.width / 2 - 140
            y: 14
        }

        Text {
            text: aiScore
            color: "#ff5566"
            font.pixelSize: 46
            font.bold: true
            x: field.width / 2 + 110
            y: 14
        }

        Text {
            text: "rally: " + rallyCount + "   difficulty: " + totalScore
            color: "#65707f"
            font.pixelSize: 12
            x: field.width / 2 - 120
            y: field.height - 24
        }

        Text {
            text: "Move: W/S or Up/Down"
            color: "#56606b"
            font.pixelSize: 12
            x: 12
            y: field.height - 24
        }

        Rectangle {
            id: ball
            width: ballRadius * 2
            height: ballRadius * 2
            radius: width / 2
            color: "#ffe082"
            x: ballX - ballRadius
            y: ballY - ballRadius
        }

        Rectangle {
            id: playerPaddle
            x: 28
            y: field.height / 2 - paddleHeight / 2
            width: paddleWidth
            height: paddleHeight
            radius: 4
            color: "#57c7ff"
        }

        Rectangle {
            id: aiPaddle
            x: field.width - paddleWidth - 28
            y: field.height / 2 - paddleHeight / 2
            width: paddleWidth
            height: paddleHeight
            radius: 4
            color: "#ff5566"
        }

        Rectangle {
            id: overlay
            anchors.fill: parent
            visible: gameOver
            color: "#d6000000"

            Text {
                id: resultText
                anchors.centerIn: parent
                text: playerScore > aiScore ? "You win!" : "AI wins!"
                color: "white"
                font.pixelSize: 48
                font.bold: true
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: resultText.y + 70
                text: "Press R/Space/Enter or click restart"
                color: "#aab2bd"
                font.pixelSize: 14
            }

            Rectangle {
                id: restartButton
                width: 170
                height: 46
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 110
                radius: 8
                color: "#2d8f65"

                Text {
                    anchors.centerIn: parent
                    text: "Restart"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 18
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: gameWindow.restartGame()
                }
            }
        }
    }

    // ---------------------------------------------------------------------
    // Input
    // ---------------------------------------------------------------------

    Item {
        id: inputLayer
        anchors.fill: parent
        focus: true

        onActiveFocusChanged: {
            if (!activeFocus) {
                upPressed = false;
                downPressed = false;
            }
        }

        Keys.onPressed: function(event) {
            if (gameOver && (event.key === Qt.Key_Space ||
                              event.key === Qt.Key_R ||
                              event.key === Qt.Key_Return ||
                              event.key === Qt.Key_Enter)) {
                gameWindow.restartGame();
                event.accepted = true;
                return;
            }

            if (event.key === Qt.Key_Up || event.key === Qt.Key_W) {
                upPressed = true;
                event.accepted = true;
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_S) {
                downPressed = true;
                event.accepted = true;
            }
        }

        Keys.onReleased: function(event) {
            if (event.key === Qt.Key_Up || event.key === Qt.Key_W) {
                upPressed = false;
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_S) {
                downPressed = false;
            }
        }
    }

    Timer {
        id: gameTimer
        interval: 16
        running: !gameOver
        repeat: true
        onTriggered: step()
    }

    Component.onCompleted: {
        playerPaddle.y = field.height / 2 - paddleHeight / 2;
        aiPaddle.y = field.height / 2 - paddleHeight / 2;
        serveBall();

        Qt.callLater(function() {
            inputLayer.forceActiveFocus();
        });
    }

    // ---------------------------------------------------------------------
    // Game logic
    // ---------------------------------------------------------------------

    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(maximum, value));
    }

    function serveSpeed() {
        return Math.min(maxBallSpeed,
                        baseBallSpeed + totalScore * 0.45);
    }

    function hitSpeed() {
        return Math.min(maxBallSpeed,
                        baseBallSpeed +
                        totalScore * 0.45 +
                        rallyCount * 0.22);
    }

    function playerSpeed() {
        return Math.min(14,
                        basePlayerSpeed + totalScore * 0.22);
    }

    function aiSpeed() {
        return Math.min(12,
                        baseAISpeed +
                        totalScore * 0.35 +
                        rallyCount * 0.09);
    }

    function serveBall() {
        if (gameOver)
            return;

        ballX = field.width / 2;
        ballY = field.height / 2;
        rallyCount = 0;

        var speed = serveSpeed();

        // Alternate serve direction after each point.
        var dir = (totalScore % 2 === 0) ? 1 : -1;

        // Random serve angle, limited to about +/- 36 degrees.
        var angle = (Math.random() * 2 - 1) * (Math.PI / 5);

        ballVelX = dir * speed * Math.cos(angle);
        ballVelY = speed * Math.sin(angle);
    }

    function step() {
        if (gameOver)
            return;

        // Player paddle movement
        var pSpeed = playerSpeed();

        if (upPressed) {
            playerPaddle.y = clamp(playerPaddle.y - pSpeed,
                                   0,
                                   field.height - paddleHeight);
        }

        if (downPressed) {
            playerPaddle.y = clamp(playerPaddle.y + pSpeed,
                                   0,
                                   field.height - paddleHeight);
        }

        // AI paddle movement.
        // If ball is moving toward AI, track it. Otherwise return to center.
        var target = (ballVelX > 0) ? ballY : (field.height / 2);
        var aiCenter = aiPaddle.y + paddleHeight / 2;
        var aiDelta = clamp(target - aiCenter, -aiSpeed(), aiSpeed());

        aiPaddle.y = clamp(aiPaddle.y + aiDelta,
                           0,
                           field.height - paddleHeight);

        // Move ball
        ballX += ballVelX;
        ballY += ballVelY;

        // Top/bottom wall bounce
        if (ballY < ballRadius) {
            ballY = ballRadius;

            if (ballVelY < 0)
                ballVelY = -ballVelY;
        } else if (ballY > field.height - ballRadius) {
            ballY = field.height - ballRadius;

            if (ballVelY > 0)
                ballVelY = -ballVelY;
        }

        // Player paddle collision
        if (ballVelX < 0 &&
            ballX <= playerPaddle.x + paddleWidth + ballRadius &&
            ballX >= playerPaddle.x - ballRadius &&
            ballY + ballRadius >= playerPaddle.y &&
            ballY - ballRadius <= playerPaddle.y + paddleHeight) {

            ballX = playerPaddle.x + paddleWidth + ballRadius;

            var playerOffset =
                (ballY - (playerPaddle.y + paddleHeight / 2)) /
                (paddleHeight / 2);

            playerOffset = clamp(playerOffset, -1, 1);

            // Avoid perfectly horizontal returns.
            if (Math.abs(playerOffset) < 0.05) {
                playerOffset = (Math.random() < 0.5 ? -1 : 1) * 0.05;
            }

            var playerHitSpeed = hitSpeed();
            var playerAngle = playerOffset * (Math.PI / 4);

            ballVelX = playerHitSpeed * Math.cos(playerAngle);
            ballVelY = playerHitSpeed * Math.sin(playerAngle);

            rallyCount += 1;
        }

        // AI paddle collision
        if (ballVelX > 0 &&
            ballX + ballRadius >= aiPaddle.x &&
            ballX <= aiPaddle.x + paddleWidth + ballRadius &&
            ballY + ballRadius >= aiPaddle.y &&
            ballY - ballRadius <= aiPaddle.y + paddleHeight) {

            ballX = aiPaddle.x - ballRadius;

            var aiOffset =
                (ballY - (aiPaddle.y + paddleHeight / 2)) /
                (paddleHeight / 2);

            aiOffset = clamp(aiOffset, -1, 1);

            // Avoid perfectly horizontal returns.
            if (Math.abs(aiOffset) < 0.05) {
                aiOffset = (Math.random() < 0.5 ? -1 : 1) * 0.05;
            }

            var aiHitSpeed = hitSpeed();
            var aiAngle = aiOffset * (Math.PI / 4);

            ballVelX = -aiHitSpeed * Math.cos(aiAngle);
            ballVelY = aiHitSpeed * Math.sin(aiAngle);

            rallyCount += 1;
        }

        // Left side miss: AI scores
        if (ballX <= 0) {
            aiScore += 1;

            if (aiScore >= winScore) {
                gameOver = true;
            } else {
                serveBall();
            }

            return;
        }

        // Right side miss: Player scores
        if (ballX >= field.width) {
            playerScore += 1;

            if (playerScore >= winScore) {
                gameOver = true;
            } else {
                serveBall();
            }

            return;
        }
    }

    function restartGame() {
        playerScore = 0;
        aiScore = 0;
        rallyCount = 0;
        upPressed = false;
        downPressed = false;
        gameOver = false;

        playerPaddle.y = field.height / 2 - paddleHeight / 2;
        aiPaddle.y = field.height / 2 - paddleHeight / 2;

        serveBall();
        gameTimer.restart();

        Qt.callLater(function() {
            inputLayer.forceActiveFocus();
        });
    }
  }

