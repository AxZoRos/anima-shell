pragma Singleton

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Models
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property list<string> smartArg: GlobalConfig.services.smartScheme ? [] : ["--no-smart"]
    readonly property string fallback: Quickshell.shellPath("assets/wallpaper.webp")
    readonly property alias isScanning: thumbQueue.isScanning
    readonly property alias isGenerating: thumbQueue.isGenerating
    readonly property alias queueRemaining: thumbQueue.queueRemaining

    property bool showPreview: false
    property bool enableAnimation: true
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    property bool previewColourLock
    property bool pendingPreviewClear

    readonly property list<string> validVideoExtensions: ["mp4", "webm", "mkv"]

    property int filterMode: 2
    property string selectedCategory: "All"
    property int badgeMode: 0

    property string rollbackPath: ""
    property string rollbackMode: ""
    property bool isTrackingRollback: false

    property string lastStatic: ""
    property string lastAnimated: ""
    property var categoryMemory: ({})

    property bool _stateLoaded: false
    property var propertiesCache: ({})
    property var parsedPropertiesMap: ({})
    property var _hashCache: ({})

    property var badgesConfig: ({
            "formatCorner": "topLeft",
            "fpsCorner": "topRight",
            "bitrateCorner": "bottomLeft"
        })

    property var rawEntries: []
    property var categories: ["All"]
    property var categoriesWithVideos: new Set()
    property var categoriesWithStatics: new Set()

    WallpaperThumbQueue {
        id: thumbQueue
        rawEntries: root.rawEntries
        actualCurrent: root.actualCurrent
        lastAnimated: root.lastAnimated
        onReloadProperties: propsFileView.reload()
    }

    readonly property alias allThumbsReady: thumbQueue.allThumbsReady
    readonly property alias itemBusters: thumbQueue.itemBusters
    readonly property alias cacheBuster: thumbQueue.cacheBuster
    readonly property alias workerCount: thumbQueue.workerCount
    readonly property alias dynamicBatchSize: thumbQueue.dynamicBatchSize

    function startSpiralQueue(centerPathHint) {
        thumbQueue.startSpiralQueue(centerPathHint);
    }
    function requestThumbnail(pathStr) {
        thumbQueue.requestThumbnail(pathStr);
    }
    function refreshAnimatedThumbs() {
        root.propertiesCache = ({});
        root.parsedPropertiesMap = ({});
        thumbQueue.refreshAnimatedThumbs();
    }

    // Memoized metadata resolver avoiding delegate regex re-evaluations
    function getParsedProperty(path) {
        if (!path)
            return {
                format: "",
                fps: "",
                bitrate: "",
                resolution: ""
            };

        let cleanPath = String(path).replace(/^file:\/\//, "");
        try {
            cleanPath = decodeURIComponent(cleanPath);
        } catch (e) {}
        if (root.parsedPropertiesMap[cleanPath]) {
            return root.parsedPropertiesMap[cleanPath];
        }

        const cleanUrl = String(path).split(/[?#]/)[0];
        const realExt = cleanUrl.split(".").pop().toUpperCase();

        if (!isVideo(cleanPath)) {
            const staticObj = {
                format: realExt,
                fps: "",
                bitrate: "",
                resolution: ""
            };
            root.parsedPropertiesMap[cleanPath] = staticObj;
            return staticObj;
        }

        let raw = root.propertiesCache[cleanPath] || root.propertiesCache["file://" + cleanPath];
        if (!raw) {
            const fileName = cleanPath.split("/").pop();
            for (let p in root.propertiesCache) {
                if (p.endsWith("/" + fileName)) {
                    raw = root.propertiesCache[p];
                    break;
                }
            }
        }

        if (!raw) {
            return {
                format: realExt,
                fps: "",
                bitrate: "",
                resolution: ""
            };
        }

        let result = null;

        if (typeof raw === "object") {
            result = {
                resolution: raw.resolution || "",
                format: (raw.format || realExt).toUpperCase(),
                fps: raw.fps || "",
                bitrate: raw.bitrate || ""
            };
        } else {
            const text = String(raw);
            const parts = text.split(", ");
            if (parts.length >= 2) {
                result = {
                    resolution: parts[0] || "",
                    format: (parts[1] || realExt).toUpperCase(),
                    fps: parts.length >= 3 ? parts[2].toLowerCase() : "",
                    bitrate: parts.length >= 4 ? parts[3] : ""
                };
            } else {
                result = {
                    format: realExt,
                    fps: "",
                    bitrate: "",
                    resolution: ""
                };
            }
        }

        root.parsedPropertiesMap[cleanPath] = result;
        return result;
    }

    readonly property var cornerCycle: ["topLeft", "topRight", "bottomRight", "bottomLeft"]

    // Rotates badge position clockwise and handles corner swapping
    function cycleBadgeCorner(type: string): void {
        let cfg = Object.assign({}, badgesConfig);
        let current = cfg[type + "Corner"] || "none";
        if (current === "none")
            current = "bottomLeft";
        let idx = cornerCycle.indexOf(current);
        let nextCorner = cornerCycle[(idx + 1) % cornerCycle.length];

        for (let k in cfg) {
            if (k !== (type + "Corner") && cfg[k] === nextCorner) {
                cfg[k] = current;
            }
        }
        cfg[type + "Corner"] = nextCorner;
        badgesConfig = cfg;
        saveBadgesConfig();
    }

    // Dismisses specific badge overlay
    function hideBadge(type: string): void {
        let cfg = Object.assign({}, badgesConfig);
        cfg[type + "Corner"] = "none";
        badgesConfig = cfg;
        saveBadgesConfig();
    }

    function saveBadgesConfig(): void {
        let jsonStr = JSON.stringify(badgesConfig, null, 2);
        Quickshell.execDetached(["sh", "-c", "mkdir -p " + shellQuote(Paths.config + "/caelestia") + " && echo " + shellQuote(jsonStr) + " > " + shellQuote(Paths.config + "/caelestia/badges.json")]);
    }

    // Toggles between 0 (All active) and 1 (Globally hidden)
    function cycleBadgeMode(): void {
        root.badgeMode = root.badgeMode === 0 ? 1 : 0;
        if (root.badgeMode === 0) {
            let cfg = Object.assign({}, badgesConfig);
            if (cfg.formatCorner === "none")
                cfg.formatCorner = "topLeft";
            if (cfg.fpsCorner === "none")
                cfg.fpsCorner = "topRight";
            if (cfg.bitrateCorner === "none")
                cfg.bitrateCorner = "bottomLeft";
            badgesConfig = cfg;
            saveBadgesConfig();
        }
        saveUiState();
    }

    function updateRawEntries() {
        if (!allWallpapers.entries) {
            root.rawEntries = [];
            root.categories = ["All"];
            root.categoriesWithVideos = new Set();
            root.categoriesWithStatics = new Set();
            return;
        }

        let entries = Array.from(allWallpapers.entries);
        let seen = new Set();
        let uniqueEntries = [];
        for (let i = 0; i < entries.length; i++) {
            let item = entries[i];
            if (item && item.path && !seen.has(item.path)) {
                seen.add(item.path);
                uniqueEntries.push(item);
            }
        }
        root.rawEntries = uniqueEntries;

        let vSet = new Set();
        let sSet = new Set();
        let catSet = new Set();

        for (let i = 0; i < uniqueEntries.length; i++) {
            let item = uniqueEntries[i];
            let isVid = isVideo(item.path);
            let cat = getCategoryFor(item);

            if (isVid) {
                vSet.add("All");
                vSet.add(cat);
            } else {
                sSet.add("All");
                sSet.add(cat);
            }

            if (cat && cat !== "All") {
                catSet.add(cat);
            }
        }

        root.categoriesWithVideos = vSet;
        root.categoriesWithStatics = sSet;

        let sortedCats = Array.from(catSet).sort((a, b) => a.localeCompare(b));
        root.categories = ["All"].concat(sortedCats);
    }

    Component.onCompleted: root.updateRawEntries()

    FileView {
        id: propsFileView
        path: `${Paths.home}/.cache/caelestia/wallpaper_properties.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.propertiesCache = JSON.parse(text().trim());
                root.parsedPropertiesMap = ({});
            } catch (e) {}
        }
    }

    FileView {
        path: `${Paths.config}/caelestia/badges.json`
        watchChanges: true
        printErrors: false
        onLoaded: {
            try {
                const parsed = JSON.parse(text().trim());
                if (parsed && typeof parsed === "object") {
                    root.badgesConfig = Object.assign({}, root.badgesConfig, parsed);
                }
            } catch (e) {}
        }
    }

    Timer {
        id: colorReleaseTimer
        interval: 180
        repeat: false
        onTriggered: {
            if (!previewColourLock && pendingPreviewClear) {
                Colours.showPreview = false;
                pendingPreviewClear = false;
            }
        }
    }

    function doSaveUiState() {
        if (!root._stateLoaded)
            return;
        stateSaveTimer.stop();

        let currentCats = root.categories || [];
        if (currentCats.length > 1) {
            let cleanedMem = {};
            for (let c in root.categoryMemory) {
                if (currentCats.includes(c)) {
                    cleanedMem[c] = root.categoryMemory[c];
                }
            }
            root.categoryMemory = cleanedMem;
        }

        let stateObj = {
            filterMode: root.filterMode,
            selectedCategory: root.selectedCategory,
            badgeMode: root.badgeMode,
            enableAnimation: root.enableAnimation,
            hwDecoder: WallpaperPauser.hwDecoder,
            pauseOnBattery: WallpaperPauser.pauseOnBattery,
            pauseOnWindowOverlap: WallpaperPauser.pauseOnWindowOverlap,
            lastStatic: root.lastStatic,
            lastAnimated: root.lastAnimated,
            categoryMemory: root.categoryMemory
        };
        let jsonStr = JSON.stringify(stateObj, null, 2);
        Quickshell.execDetached(["sh", "-c", "mkdir -p " + shellQuote(Paths.state + "/wallpaper") + " && echo " + shellQuote(jsonStr) + " > " + shellQuote(Paths.state + "/wallpaper/ui_state.json")]);
    }

    Timer {
        id: stateSaveTimer
        interval: 200
        repeat: false
        onTriggered: root.doSaveUiState()
    }

    function saveUiState(immediate = false) {
        if (immediate) {
            root.doSaveUiState();
        } else {
            stateSaveTimer.restart();
        }
    }

    function categoryHasVideos(cat: string): bool {
        return root.categoriesWithVideos.has(cat);
    }
    function categoryHasStatics(cat: string): bool {
        return root.categoriesWithStatics.has(cat);
    }

    function resetToApplied() {
        if (!actualCurrent)
            return;
        filterMode = isVideo(actualCurrent) ? 1 : 0;
        let cat = getCategoryForPath(actualCurrent);
        selectedCategory = (cat && categories.includes(cat)) ? cat : "All";
    }

    FileView {
        path: `${Paths.state}/wallpaper/ui_state.json`
        printErrors: false
        onLoaded: {
            try {
                const parsed = JSON.parse(text().trim());
                if (parsed && typeof parsed === "object") {
                    if (parsed.lastStatic !== undefined)
                        root.lastStatic = parsed.lastStatic;
                    if (parsed.lastAnimated !== undefined)
                        root.lastAnimated = parsed.lastAnimated;
                    if (parsed.categoryMemory !== undefined)
                        root.categoryMemory = parsed.categoryMemory;
                    if (parsed.badgeMode !== undefined)
                        root.badgeMode = parsed.badgeMode;
                    if (parsed.enableAnimation !== undefined)
                        root.enableAnimation = parsed.enableAnimation;
                    if (parsed.hwDecoder !== undefined)
                        WallpaperPauser.hwDecoder = parsed.hwDecoder;
                    if (parsed.pauseOnBattery !== undefined)
                        WallpaperPauser.pauseOnBattery = parsed.pauseOnBattery;
                    if (parsed.pauseOnWindowOverlap !== undefined)
                        WallpaperPauser.pauseOnWindowOverlap = parsed.pauseOnWindowOverlap;
                }
            } catch (e) {}
            root._stateLoaded = true;
            root.resetToApplied();
        }
        onLoadFailed: {
            root._stateLoaded = true;
            root.resetToApplied();
        }
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'";
    }

    function djb2_hash(s) {
        if (!s)
            return "0";
        if (_hashCache[s] !== undefined)
            return _hashCache[s];
        let h = 5381;
        for (let i = 0; i < s.length; i++) {
            h = ((h << 5) + h) + s.charCodeAt(i);
            h |= 0;
        }
        const res = (h >>> 0).toString(10);
        _hashCache[s] = res;
        return res;
    }

    function getRawThumbPath(path) {
        let clean = String(path || "").split(/[?#]/)[0].replace(/^file:\/\//, "");
        try {
            clean = decodeURIComponent(clean);
        } catch (e) {}
        let fileName = clean.split("/").pop();
        return Paths.cache + "/videothumbs/" + djb2_hash(fileName) + ".jpg";
    }

    function getWallpaperThumb(path, buster) {
        let b = buster || "";
        return "file://" + getRawThumbPath(path) + (b ? "?v=" + b : "");
    }

    function isVideo(path: string): bool {
        if (!path)
            return false;
        const clean = String(path || "").split(/[?#]/)[0].toLowerCase();
        const index = clean.lastIndexOf(".");
        const ext = index >= 0 ? clean.slice(index + 1) : "";
        return validVideoExtensions.includes(ext);
    }

    function indexOf(path: string): int {
        if (!path)
            return -1;
        let clean = String(path).split(/[?#]/)[0].replace(/^file:\/\//, "");

        for (let i = 0; i < list.length; i++) {
            let p = String(list[i].path || "").split(/[?#]/)[0].replace(/^file:\/\//, "");
            if (p === clean)
                return i;
        }
        return -1;
    }

    function getCategoryFor(w: FileSystemEntry): string {
        if (!w || !w.parentDir)
            return "All";
        return getCategoryForPath(w.parentDir);
    }

    function getCategoryForPath(pathStr: string): string {
        if (!pathStr)
            return "All";
        let clean = String(pathStr).replace(/^file:\/\//, "");
        let base = String(Paths.wallsdir || "").replace(/^file:\/\//, "");

        if (base.endsWith("/"))
            base = base.slice(0, -1);
        if (clean.endsWith("/"))
            clean = clean.slice(0, -1);

        if (clean === base || clean.length <= base.length)
            return "All";

        if (clean.startsWith(base + "/")) {
            let rel = clean.slice(base.length + 1);
            let parts = rel.split("/");
            return parts[0] || "All";
        }
        return "All";
    }

    onCategoriesChanged: {
        if (root.rawEntries.length > 0 && categories && categories.length > 1) {
            if (!categories.includes(selectedCategory)) {
                selectedCategory = "All";
            }
        }
    }

    function captureRollbackState() {
        if (!isTrackingRollback) {
            rollbackPath = actualCurrent;
            rollbackMode = filterMode;
            isTrackingRollback = true;
        }
    }

    onEnableAnimationChanged: saveUiState()
    onFilterModeChanged: saveUiState()

    function setRandom(): void {
        if (list && list.length > 0) {
            let randomIndex = Math.floor(Math.random() * list.length);
            setWallpaper(list[randomIndex].path);
        } else {
            Quickshell.execDetached(["caelestia", "wallpaper", "-r", ...smartArg]);
        }
    }

    function setWallpaper(path: string): void {
        let clean = String(path || "").split(/[?#]/)[0].replace(/^file:\/\//, "");
        if (!clean)
            return;

        actualCurrent = clean;
        isTrackingRollback = false;

        previewColourLock = true;
        pendingPreviewClear = false;

        let cat = getCategoryForPath(clean);
        if (cat !== "All") {
            let mem = Object.assign({}, categoryMemory);
            mem[cat] = clean;
            categoryMemory = mem;
        }

        if (isVideo(clean)) {
            lastAnimated = clean;
        } else {
            lastStatic = clean;
        }

        saveUiState();
        Quickshell.execDetached(["caelestia", "wallpaper", "-f", clean, ...smartArg]);
    }

    function preview(path: string): void {
        let clean = String(path || "").split(/[?#]/)[0].replace(/^file:\/\//, "");
        if (!clean)
            return;

        if (clean === actualCurrent && !showPreview)
            return;
        if (previewPath === clean && showPreview)
            return;

        captureRollbackState();
        previewPath = clean;
        showPreview = true;

        if (String(Colours.scheme).startsWith("dynamic")) {
            getPreviewColoursProc.startFor(clean);
        }
    }

    function stopPreview(): void {
        if (!showPreview && !isTrackingRollback)
            return;
        showPreview = false;

        if (getPreviewColoursProc.running) {
            getPreviewColoursProc.running = false;
        }

        if (isTrackingRollback) {
            const targetPath = rollbackPath;
            isTrackingRollback = false;

            actualCurrent = targetPath;
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", targetPath, ...smartArg]);
        }

        if (previewColourLock) {
            pendingPreviewClear = true;
        } else {
            Colours.showPreview = false;
            pendingPreviewClear = false;
        }
    }

    onPreviewColourLockChanged: {
        if (!previewColourLock && pendingPreviewClear) {
            colorReleaseTimer.restart();
        }
    }

    readonly property var filteredEntries: {
        let res = [];
        let seen = new Set();
        for (let i = 0; i < root.rawEntries.length; i++) {
            let item = root.rawEntries[i];
            if (!item || !item.path || seen.has(item.path))
                continue;

            let isVid = isVideo(item.path);

            if (filterMode === 0 && isVid)
                continue;
            if (filterMode === 1 && !isVid)
                continue;

            if (selectedCategory !== "All") {
                let cat = getCategoryFor(item);
                if (cat !== selectedCategory)
                    continue;
            }

            seen.add(item.path);
            res.push(item);
        }
        return res;
    }

    list: filteredEntries
    key: "name"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    IpcHandler {
        function get(): string {
            return root.actualCurrent;
        }
        function set(path: string): void {
            root.setWallpaper(path);
        }
        function list(): string {
            return root.list.map(w => w.path).join("\n");
        }
        target: "wallpaper"
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let wall = text().trim();
            if (!wall) {
                wall = root.fallback;
                Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
            }
            root.actualCurrent = wall;
            root.previewColourLock = false;

            let changed = false;
            if (root.isVideo(root.actualCurrent)) {
                if (!root.lastAnimated) {
                    root.lastAnimated = wall;
                    changed = true;
                }
            } else {
                if (!root.lastStatic) {
                    root.lastStatic = wall;
                    changed = true;
                }
            }
            if (changed)
                saveUiState();
            root.resetToApplied();
        }
        onLoadFailed: {
            root.actualCurrent = root.fallback;
            root.previewColourLock = false;
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
        }
    }

    FileSystemModel {
        id: allWallpapers
        watchChanges: true
        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Files
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.tif", "*.tiff", "*.svg", "*.gif", "*.mp4", "*.webm", "*.mkv"]
        onEntriesChanged: {
            thumbQueue.failedAttempts = ({});
            root.updateRawEntries();
            if (thumbQueue._pendingSpiralTarget !== "") {
                thumbQueue.startSpiralQueue(thumbQueue._pendingSpiralTarget);
            }
        }
    }

    Process {
        id: getPreviewColoursProc
        property string currentProcessingPath: ""
        property string pendingPath: ""
        property real startTime: 0

        command: ["caelestia", "wallpaper", "-p", currentProcessingPath, ...root.smartArg]

        function startFor(path) {
            if (!path)
                return;
            if (running) {
                pendingPath = path;
                return;
            }

            pendingPath = "";
            currentProcessingPath = path;
            startTime = Date.now();
            running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.showPreview)
                    return;
                const raw = text ? text.trim() : "";
                if (raw) {
                    try {
                        JSON.parse(raw);
                        Colours.load(raw, true);
                        Colours.showPreview = true;
                    } catch (e) {}
                }

                if (getPreviewColoursProc.pendingPath !== "" && getPreviewColoursProc.pendingPath !== getPreviewColoursProc.currentProcessingPath) {
                    const next = getPreviewColoursProc.pendingPath;
                    getPreviewColoursProc.pendingPath = "";
                    getPreviewColoursProc.startFor(next);
                }
            }
        }
    }
}
