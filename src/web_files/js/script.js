const data = `/data.json`;
fetch(data).then((r) => r.json()).then((data) => {
    new Chart(document.querySelector("canvas").getContext("2d"), {
        type: 'forceDirectedGraph',
        data: {
            labels: data.nodes.map((d) => d.label),
            datasets: [{
                pointBackgroundColor: 'steelblue',
                pointRadius: 5,
                data: data.nodes,
                edges: data.links
            }]
        },
        options: {
            plugins: {
                datalabels: {
                  display: true,
                  align: "top"
                },
                dragData:  false,
              }
            },
        plugins: [ChartDataLabels],
    });
});