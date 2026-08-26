pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import Caelestia.Models
import qs.services
import qs.utils

Item {
    id: root

    property var rawEntries: []
    property string actualCurrent: ""
    property string lastAnimated: ""

    property bool allThumbsReady: false
    property var itemBusters: ({})
    property string cacheBuster: "1"
    property var failedAttempts: ({})

    property var existingThumbHashes: new Set()

    readonly property bool isScanning: _refreshing || _pendingSpiralTarget !== ""
    readonly property bool isGenerating: _queueWorkerProc.running || (!allThumbsReady && generationQueue.length > 0)
    readonly property int queueRemaining: generationQueue.length

    property int cpuThreads: 1
    readonly property int workerCount: Math.min(8, Math.max(1, Math.floor(cpuThreads / 2)))
    readonly property int dynamicBatchSize: workerCount * 4

    property var generationQueue: []
    property var priorityQueue: []
    property bool _refreshing: false
    property string _pendingSpiralTarget: ""

    readonly property list<string> validVideoExtensions: ["mp4", "webm", "mkv"]

    signal reloadProperties

    function isVideo(path) {
        if (!path)
            return false;
        const clean = String(path || "").split(/[?#]/)[0].toLowerCase();
        const index = clean.lastIndexOf(".");
        const ext = index >= 0 ? clean.slice(index + 1) : "";
        return validVideoExtensions.includes(ext);
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'";
    }

    function isPropsCached(cleanPath) {
        if (!Wallpapers.propertiesCache)
            return false;
        return (Wallpapers.propertiesCache[cleanPath] !== undefined || Wallpapers.propertiesCache["file://" + cleanPath] !== undefined);
    }

    FileSystemModel {
        id: thumbFiles
        path: `${Paths.cache}/videothumbs`
        watchChanges: true
        filter: FileSystemModel.Files
        nameFilters: ["*.jpg"]
        onEntriesChanged: {
            if (!_queueWorkerProc.running) {
                thumbUpdateDebounce.restart();
            }
        }
    }

    onRawEntriesChanged: {
        thumbUpdateDebounce.restart();
        if (rawEntries && rawEntries.length > 0) {
            let videoList = rawEntries.filter(w => isVideo(w.path));
            if (videoList.length === 0) {
                root._pendingSpiralTarget = "";
                root.allThumbsReady = true;
                root.generationQueue = [];
            } else if (root._pendingSpiralTarget !== "") {
                let target = root._pendingSpiralTarget;
                root._pendingSpiralTarget = "";
                root.startSpiralQueue(target);
            }
        }
    }

    Timer {
        id: thumbUpdateDebounce
        interval: 60
        repeat: false
        onTriggered: root.doUpdateExistingThumbs()
    }

    function doUpdateExistingThumbs() {
        let set = new Set();
        if (thumbFiles.entries) {
            let entries = Array.from(thumbFiles.entries);
            for (let i = 0; i < entries.length; i++) {
                let name = entries[i].name;
                if (name.endsWith(".jpg")) {
                    set.add(name.slice(0, -4));
                }
            }
        }
        root.existingThumbHashes = set;
        if (!root.rawEntries || root.rawEntries.length === 0) {
            root.allThumbsReady = true;
            return;
        }

        let videoList = root.rawEntries.filter(w => isVideo(w.path));
        if (videoList.length === 0) {
            root.allThumbsReady = true;
            root._pendingSpiralTarget = "";
            root.generationQueue = [];
            return;
        }

        let missingCount = 0;
        for (let i = 0; i < videoList.length; i++) {
            let clean = String(videoList[i].path || "").split(/[?#]/)[0].replace(/^file:\/\//, "");
            let fileName = clean.split("/").pop();
            let h = Wallpapers.djb2_hash(fileName);
            let hasThumb = set.has(h);
            let hasProps = root.isPropsCached(clean);
            let isFailed = (root.failedAttempts[clean] || 0) >= 5;
            if ((!hasThumb || !hasProps) && !isFailed) {
                missingCount++;
            }
        }

        root.allThumbsReady = (missingCount === 0);
    }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", `${Paths.cache}/videothumbs`]);
        doUpdateExistingThumbs();
    }

    FileView {
        path: "/sys/devices/system/cpu/online"
        printErrors: false
        onLoaded: {
            try {
                let str = text().trim();
                let totalCores = 0;
                let groups = str.split(",");
                for (let i = 0; i < groups.length; i++) {
                    let bounds = groups[i].split("-");
                    if (bounds.length === 2) {
                        let start = parseInt(bounds[0], 10);
                        let end = parseInt(bounds[1], 10);
                        if (!isNaN(start) && !isNaN(end) && end >= start) {
                            totalCores += (end - start + 1);
                        }
                    } else if (bounds.length === 1) {
                        let single = parseInt(bounds[0], 10);
                        if (!isNaN(single)) {
                            totalCores += 1;
                        }
                    }
                }
                if (totalCores > 0) {
                    root.cpuThreads = totalCores;
                }
            } catch (e) {}
        }
    }

    function startSpiralQueue(centerPathHint) {
        if (!rawEntries || rawEntries.length === 0) {
            root._pendingSpiralTarget = centerPathHint || actualCurrent || "";
            return;
        }
        let videoList = rawEntries.filter(w => isVideo(w.path));
        if (videoList.length === 0) {
            root._pendingSpiralTarget = "";
            root.allThumbsReady = true;
            root.generationQueue = [];
            return;
        }
        root._pendingSpiralTarget = "";

        if (allThumbsReady && !_refreshing) {
            return;
        }

        let missingVideos = [];
        let seenMissingPaths = new Set();

        for (let i = 0; i < videoList.length; i++) {
            let clean = String(videoList[i].path || "").split(/[?#]/)[0].replace(/^file:\/\//, "");
            let fileName = clean.split("/").pop();
            let h = Wallpapers.djb2_hash(fileName);
            let hasThumb = root.existingThumbHashes.has(h);
            let hasProps = root.isPropsCached(clean);
            let isFailed = (root.failedAttempts[clean] || 0) >= 2;
            if ((!hasThumb || !hasProps) && !isFailed && !seenMissingPaths.has(clean)) {
                missingVideos.push(videoList[i]);
                seenMissingPaths.add(clean);
            }
        }

        if (missingVideos.length === 0 && !_refreshing) {
            root.allThumbsReady = true;
            root.generationQueue = [];
            return;
        }

        let targetList = _refreshing ? videoList : missingVideos;
        let target = centerPathHint || actualCurrent || lastAnimated || "";
        let cleanTarget = String(target).replace(/^file:\/\//, "");
        let c = targetList.findIndex(w => String(w.path).replace(/^file:\/\//, "") === cleanTarget);
        if (c < 0)
            c = 0;

        let total = targetList.length;
        let spiralPaths = [];
        let addedPaths = new Set();

        let centerClean = String(targetList[c].path || "").replace(/^file:\/\//, "");
        spiralPaths.push(centerClean);
        addedPaths.add(centerClean);
        for (let offset = 1; offset < total; offset++) {
            let rIdx = (c + offset) % total;
            let rPath = String(targetList[rIdx].path || "").replace(/^file:\/\//, "");
            if (!addedPaths.has(rPath)) {
                spiralPaths.push(rPath);
                addedPaths.add(rPath);
            }

            let lIdx = ((c - offset) % total + total) % total;
            let lPath = String(targetList[lIdx].path || "").replace(/^file:\/\//, "");
            if (!addedPaths.has(lPath)) {
                spiralPaths.push(lPath);
                addedPaths.add(lPath);
            }
        }

        let remainingPriority = root.priorityQueue.filter(p => p !== "");
        root.generationQueue = remainingPriority.concat(spiralPaths.filter(p => !remainingPriority.includes(p)));
        triggerQueueProcess();
    }

    function requestThumbnail(pathStr) {
        if (!pathStr)
            return;
        let clean = String(pathStr).replace(/^file:\/\//, "");
        if (!isVideo(clean) || (root.failedAttempts[clean] || 0) >= 5)
            return;

        root.allThumbsReady = false;
        if (!root.priorityQueue.includes(clean)) {
            root.priorityQueue.unshift(clean);
        }
        let existingIdx = root.generationQueue.indexOf(clean);
        if (existingIdx >= 0) {
            root.generationQueue.splice(existingIdx, 1);
        }
        root.generationQueue.unshift(clean);
        triggerQueueProcess();
    }

    function triggerQueueProcess() {
        if (_queueWorkerProc.running || generationQueue.length === 0)
            return;
        let batch = generationQueue.slice(0, root.dynamicBatchSize);
        _queueWorkerProc.currentBatch = batch;

        let queuePath = Paths.cache + "/thumb_queue.json";
        let cmd = "mkdir -p " + shellQuote(Paths.cache) + " && cat << 'EOF' > " + shellQuote(queuePath) + "\n" + JSON.stringify(batch) + "\nEOF\ncaelestia wallpaper --extract-thumbs";
        _queueWorkerProc.command = ["sh", "-c", cmd];
        _queueWorkerProc.running = true;
        batchWatchdogTimer.restart();
    }

    Timer {
        id: batchWatchdogTimer
        interval: 45000
        repeat: false
        onTriggered: {
            if (_queueWorkerProc.running) {
                _queueWorkerProc.running = false;
                Qt.callLater(root.triggerQueueProcess);
            }
        }
    }

    Process {
        id: _queueWorkerProc
        property var currentBatch: []

        stdout: StdioCollector {
            onStreamFinished: {
                if (!text)
                    return;
                let lines = text.split("\n");
                let busters = Object.assign({}, root.itemBusters);
                let fails = Object.assign({}, root.failedAttempts);
                let now = Date.now().toString();
                let count = 0;

                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (line.startsWith("READY:")) {
                        let p = line.substring(6).trim();
                        busters[p] = now;
                        busters["file://" + p] = now;
                        delete fails[p];
                        count++;
                    } else if (line.startsWith("FAILED:")) {
                        let p = line.substring(7).trim();
                        fails[p] = (fails[p] || 0) + 1;
                    }
                }
                root.failedAttempts = fails;
                if (count > 0) {
                    root.itemBusters = busters;
                    root.cacheBuster = now;
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            batchWatchdogTimer.stop();
            let now = Date.now().toString();
            root.cacheBuster = now;
            root.reloadProperties();

            if (currentBatch && currentBatch.length > 0) {
                let batchSet = new Set(currentBatch);
                root.generationQueue = root.generationQueue.filter(p => !batchSet.has(p));
                root.priorityQueue = root.priorityQueue.filter(p => !batchSet.has(p));
                currentBatch = [];
            }
            if (root._refreshing) {
                root._refreshing = false;
            }
            if (root.generationQueue.length > 0) {
                Qt.callLater(root.triggerQueueProcess);
            } else {
                root.allThumbsReady = true;
            }
        }
    }

    function refreshAnimatedThumbs() {
        if (_queueWorkerProc.running || _refreshing)
            return;
        itemBusters = ({});
        generationQueue = [];
        priorityQueue = [];
        failedAttempts = ({});
        allThumbsReady = false;
        _refreshing = true;
        _pendingSpiralTarget = "";

        startSpiralQueue(actualCurrent);
    }
}
