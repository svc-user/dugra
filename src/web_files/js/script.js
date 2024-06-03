let filterBox = document.querySelector("#filter");
filterBox.addEventListener("keyup", filterBoxChangedDebounce);
filterBox.addEventListener("change", filterBoxChangedDebounce);

function nodeClickHandler(_, active) {
    if (active.length < 1) return;

    let idx = active[0].index;
    let name = _oldChart.data.labels[idx];
    filterBox.value = name;
    filterBox.dispatchEvent(new Event("change"));
}

let _oldChart = {};
let _data = [];
function loadData() {
    if (_data.length === 0) {
        fetch('/data.json').then((r) => r.json()).then(d => {
            _data = d;
            updateChart(structuredClone(d));
        });
    } else {
        updateChart(structuredClone(_data));
    }
}
loadData();

function updateChart(data) {
    let dataset = filterData(data);
    dataset = dataset.sort((a, b) => a.id - b.id);
    dataset = updateIds(dataset);

    if (typeof _oldChart.destroy !== "undefined") _oldChart.destroy();

    _oldChart = new Chart(document.querySelector("canvas").getContext("2d"), {
        type: 'dendrogram',
        data: {
            labels: dataset.map(d => d.name),
            datasets: [{
                pointBackgroundColor: 'steelblue',
                pointRadius: 5,
                data: dataset,
            }]
        },
        options: {
            plugins: {
                plugins: {
                    datalabels: {
                        display: false,
                        position: "top"
                    },
                },
            },
            onClick: nodeClickHandler,
            layout: {
                padding: 80,
            },
        },
        plugins: [ChartDataLabels],
    });
}


function filterData(data) {
    console.log(filterBox.value);

    let filtered = structuredClone(data);
    filtered = filtered.filter(n => n.name.toLowerCase().indexOf(filterBox.value.toLowerCase()) > -1);

    let foundParents = -1;
    while (foundParents != 0) {
        foundParents = 0;

        for (let node of filtered) {
            for (let n of data) {
                if (node.parent == n.id && filtered.find(f => f.id == n.id) == undefined) {
                    console.log(node); // <-- this node
                    console.log(n); // <-- has this parent
                    console.log('-----------');

                    filtered.push(n);
                    foundParents++;
                }
            }
        }
    }

    return filtered;
}

function updateIds(data) {
    let newData = structuredClone(data);

    for (let i = 0; i < newData.length; i++) {
        let oldId = newData[i].id;
        newData[i].id = i;
        for (let j = 0; j < newData.length; j++) {
            if (newData[j].parent == oldId) {
                newData[j].parent = i;
            }
        }
    }

    return newData;
}


let filterboxChangeEvent = 0;
function filterBoxChangedDebounce() {
    clearTimeout(filterboxChangeEvent);
    filterboxChangeEvent = setTimeout(filterBoxChanged, 1000);
}

let oldFilterVal = "";
function filterBoxChanged() {
    if (oldFilterVal != filterBox.value.toLowerCase()) {
        loadData();
        oldFilterVal = filterBox.value.toLowerCase();
    }
}