function updateTitle(text) {
    document.querySelector('.extSection').textContent = text;
}

function checkChromium(requiredMajor, requiredMinor, requiredBuild, requiredPatch) {
    var userAgent = navigator.userAgent;
    var match = userAgent.match(/Chrome\/(\d+)\.(\d+)\.(\d+)\.(\d+)/);
    if (match) {
        var current = {
            major: parseInt(match[1]),
            minor: parseInt(match[2]),
            build: parseInt(match[3]),
            patch: parseInt(match[4])
        };

        var required = {
            major: requiredMajor,
            minor: requiredMinor,
            build: requiredBuild,
            patch: requiredPatch
        };

        if (current.major > required.major) return true;
        if (current.major < required.major) return false;
        if (current.minor > required.minor) return true;
        if (current.minor < required.minor) return false;
        if (current.build > required.build) return true;
        if (current.build < required.build) return false;
        return current.patch >= required.patch;
    }
    return false;
}

function loadJSON() {
    fetch('../extension.json')
        .then(response => response.json())
        .then(data => {
            document.querySelectorAll('.extName').forEach(element => {
                element.textContent = data.name;
            });
            document.querySelectorAll('.extDescription').forEach(element => {
                element.textContent = data.description;
            });
            document.querySelectorAll('.extUpdate').forEach(element => {
                element.textContent = data.update;
            });
            document.querySelectorAll('.extVersion').forEach(element => {
                element.textContent = data.version;
            });
            document.querySelectorAll('.extCopyright').forEach(element => {
                element.textContent = data.copyright;
            });
            document.querySelectorAll('.extDate').forEach(element => {
                element.textContent = data.date;
            });
            document.querySelectorAll('.extEwUrl').forEach(element => {
                element.setAttribute('href', data.ew_url);
                element.textContent = "Extension Warehouse";
            });
            document.querySelectorAll('.extGhUrl').forEach(element => {
                element.setAttribute('href', data.gh_url);
                element.textContent = "Github";
            });
            document.querySelectorAll('.extSuUrl').forEach(element => {
                element.setAttribute('href', data.su_url);
                element.textContent = "SketchUcation";
            });
        })
        .catch(error => console.error('Error loading the JSON file:', error));
}

function loadSection(section) {
    document.getElementById('modusContentFrame').src = section;
}

function thanksContent() {
    var selectedValue = document.getElementById("formSelect").value;
    var contentPrefix = "content_";
    var contentElements = document.querySelectorAll('[id^="' + contentPrefix + '"]');

    contentElements.forEach(function(contentElement) {
        contentElement.style.display = "none";
    });

    var selectedContent = document.getElementById(contentPrefix + selectedValue);
    if (selectedContent) {
        selectedContent.style.display = "block";
    }
}

document.addEventListener('DOMContentLoaded', function() {
    if (checkChromium(112, 0, 5615, 165)) {
        loadJSON();
    }
});
