let isMonitoring = false;
let detectedAnimations = [];
let favorites = [];
let isPaused = false;

// UI visibility and interaction
window.addEventListener('message', (event) => {
    const data = event.data;
    if (data.type === 'openUI') {
        document.getElementById('animtest-ui').style.display = 'flex';
    } else if (data.type === 'closeUI') {
        document.getElementById('animtest-ui').style.display = 'none';
    } else if (data.type === 'updateDetected') {
        detectedAnimations = data.animations;
        updateDetectedList();
    } else if (data.type === 'updatePlaying') {
        document.getElementById('playing').innerText = data.anim || 'NONE';
    } else if (data.type === 'updateFavorites') {
        favorites = data.favorites;
        updateFavoritesList();
    } else if (data.type === 'updateFPS') {
        document.getElementById('fps').innerText = `FPS: ${data.fps}`;
    }
});

// Toggle monitoring
document.getElementById('toggle-monitoring').addEventListener('click', () => {
    fetch(`https://${GetParentResourceName()}/toggleMonitoring`, { method: 'POST' })
        .then(resp => resp.json())
        .then(data => {
            isMonitoring = data.monitoring;
            document.getElementById('toggle-monitoring').innerText = isMonitoring ? 'Stop Monitoring' : 'Start Monitoring';
        });
});

// Minimize UI
document.getElementById('minimize').addEventListener('click', () => {
    const ui = document.getElementById('animtest-ui');
    ui.style.height = ui.style.height === '40px' ? '600px' : '40px';
    ui.style.overflow = ui.style.overflow === 'hidden' ? 'auto' : 'hidden';
});

// Search animations
document.getElementById('search-bar').addEventListener('input', (e) => {
    const query = e.target.value;
    fetch(`https://${GetParentResourceName()}/searchAnim`, {
        method: 'POST',
        body: JSON.stringify({ query })
    })
        .then(resp => resp.json())
        .then(data => {
            detectedAnimations = data.results;
            updateDetectedList();
        });
});

// Filter animations
document.getElementById('filter').addEventListener('change', (e) => {
    const filter = e.target.value;
    fetch(`https://${GetParentResourceName()}/setFilter`, {
        method: 'POST',
        body: JSON.stringify({ filter })
    });
});

// Pause/resume preview
document.getElementById('pause-resume').addEventListener('click', () => {
    fetch(`https://${GetParentResourceName()}/togglePause`, { method: 'POST' })
        .then(resp => resp.json())
        .then(data => {
            isPaused = data.paused;
            document.getElementById('pause-resume').innerText = isPaused ? 'Resume' : 'Pause';
        });
});

// Camera controls
document.querySelectorAll('.camera-controls input').forEach(input => {
    input.addEventListener('input', () => {
        const camX = parseFloat(document.getElementById('cam-x').value);
        const camY = parseFloat(document.getElementById('cam-y').value);
        const camZ = parseFloat(document.getElementById('cam-z').value);
        const camFov = parseFloat(document.getElementById('cam-fov').value);
        fetch(`https://${GetParentResourceName()}/updateCamera`, {
            method: 'POST',
            body: JSON.stringify({ x: camX, y: camY, z: camZ, fov: camFov })
        });
    });
});

// Update detected animations list
function updateDetectedList() {
    const list = document.getElementById('detected-list');
    list.innerHTML = detectedAnimations.map(anim => `
        <div class="animation-item">
            <span>${anim.dict} - ${anim.anim}</span>
            <div>
                <button onclick="previewAnim('${anim.dict}', '${anim.anim}', 2000)">Preview</button>
                <button onclick="playAnim('${anim.dict}', '${anim.anim}')">Play</button>
                <button onclick="addFavorite('${anim.dict}', '${anim.anim}')">Favorite</button>
                <button onclick="exportAnim('${anim.dict}', '${anim.anim}')">Export</button>
            </div>
        </div>
    `).join('');
}

// Update favorites list
function updateFavoritesList() {
    const list = document.getElementById('favorites-list');
    list.innerHTML = favorites.map(anim => `
        <div class="animation-item">
            <span>${anim.dict} - ${anim.anim}</span>
            <div>
                <button onclick="previewAnim('${anim.dict}', '${anim.anim}', 2000)">Preview</button>
                <button onclick="playAnim('${anim.dict}', '${anim.anim}')">Play</button>
            </div>
        </div>
    `).join('');
}

// Preview animation
function previewAnim(dict, anim, duration) {
    fetch(`https://${GetParentResourceName()}/previewAnim`, {
        method: 'POST',
        body: JSON.stringify({ dict, anim, duration })
    });
}

// Play animation
function playAnim(dict, anim) {
    fetch(`https://${GetParentResourceName()}/playAnim`, {
        method: 'POST',
        body: JSON.stringify({ dict, anim })
    });
}

// Add to favorites
function addFavorite(dict, anim) {
    fetch(`https://${GetParentResourceName()}/addFavorite`, {
        method: 'POST',
        body: JSON.stringify({ dict, anim })
    });
}

// Export animation
function exportAnim(dict, anim) {
    fetch(`https://${GetParentResourceName()}/exportAnim`, {
        method: 'POST',
        body: JSON.stringify({ dict, anim })
    })
        .then(resp => resp.json())
        .then(data => {
            alert('Exported Code:\n' + data.code);
        });
}
