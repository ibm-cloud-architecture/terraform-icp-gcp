var express = require('express');

var app = express();
var https = require('https');

app.use(express.json());
app.use(express.urlencoded({ extended: false }));


/* healthcheck  */
app.get('/healthz', function(req, res, next) {
  console.log("healthcheck called");

  var options = {
    host: '127.0.0.1',
    port: 8001,
    path: '/healthz',
    method: 'GET'
  }

  var req = https.request(options, function(resp) {
      resp.on('data', function(d) {
      });

      resp.on('end', function() {
          res.sendStatus(resp.statusCode);
      });

      resp.on('error', function(e) {
        res.sendStatus(503);
      });

  });

  req.on('socket', function (socket) {
    socket.setTimeout(2000);
    socket.on('timeout', function() {
      req.abort();
    });
  });

  req.on('error', function (e) {
      console.log(e);
      res.sendStatus(503);
  });

  req.end();


});

app.listen(3000);
