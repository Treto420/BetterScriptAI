angular.module('beamng.apps')
.directive('honkManagerApp', function() {
  return {
    templateUrl: '/ui/modules/apps/HonkManager/app.html',
    controller: 'HonkManagerCtrl',
  };
})
.controller('HonkManagerCtrl', ['$scope', '$timeout', function($scope, $timeout) {

  // ── State ──────────────────────────────────────────────
  $scope.activeTab      = 'vehicles';
  $scope.vehicles       = [];
  $scope.logEntries     = [];
  $scope.syncParticipants = [];
  $scope.syncSession    = { phase: 'idle', participants: [] };
  $scope.logFilter      = { vehicleId: '', type: '' };
  $scope.autoScroll     = true;

  // ── Helpers ─────────────────────────────────────────────
  function findVehicle(id) {
    return $scope.vehicles.find(v => v.id === id);
  }

  $scope.getVehName = function(id) {
    const v = findVehicle(id);
    return v ? v.name : ('Vehicle ' + id);
  };

  $scope.isSyncParticipant = function(id) {
    return $scope.syncParticipants.includes(id);
  };

  $scope.toggleSyncParticipant = function(id) {
    const idx = $scope.syncParticipants.indexOf(id);
    if (idx === -1) $scope.syncParticipants.push(id);
    else            $scope.syncParticipants.splice(idx, 1);
  };

  $scope.filteredLog = function() {
    return $scope.logEntries.filter(e => {
      if ($scope.logFilter.vehicleId && String(e.vehicleId) !== $scope.logFilter.vehicleId) return false;
      if ($scope.logFilter.type      && e.type !== $scope.logFilter.type)                   return false;
      return true;
    });
  };

  function scrollLog() {
    if (!$scope.autoScroll) return;
    $timeout(function() {
      const el = document.getElementById('logViewer');
      if (el) el.scrollTop = el.scrollHeight;
    }, 30);
  }

  $scope.clearLog = function() { $scope.logEntries = []; };

  $scope.copyLogEntry = function(entry) {
    const text = `[${entry.timestamp}] [${entry.type}] ${entry.message}`;
    navigator.clipboard && navigator.clipboard.writeText(text);
  };

  // ── Lua calls ───────────────────────────────────────────
  $scope.startRecording = function(id) { bngApi.engineLua(`honkManager.startRecording(${id})`); };
  $scope.stopRecording  = function(id) { bngApi.engineLua(`honkManager.stopRecording(${id})`);  };
  $scope.playback       = function(id) { bngApi.engineLua(`honkManager.playback(${id})`);       };
  $scope.stopPlayback   = function(id) { bngApi.engineLua(`honkManager.stopPlayback(${id})`);   };
  $scope.clearData      = function(id) { bngApi.engineLua(`honkManager.clearData(${id})`);      };

  $scope.triggerSync = function() {
    if ($scope.syncParticipants.length < 2) return;
    const json = JSON.stringify($scope.syncParticipants);
    bngApi.engineLua(`honkManager.syncPlayback('${json}')`);
  };

  // ── guihooks listeners ──────────────────────────────────
  $scope.$on('honkMgr_allVehicles', function(_, list) {
    $scope.$apply(function() { $scope.vehicles = list; });
  });

  $scope.$on('honkMgr_vehicleUpdate', function(_, v) {
    $scope.$apply(function() {
      const idx = $scope.vehicles.findIndex(x => x.id === v.id);
      if (idx === -1) $scope.vehicles.push(v);
      else            $scope.vehicles[idx] = v;
    });
  });

  $scope.$on('honkMgr_logEntry', function(_, entry) {
    $scope.$apply(function() {
      $scope.logEntries.push(entry);
      if ($scope.logEntries.length > 500) $scope.logEntries.shift();
    });
    scrollLog();
  });

  $scope.$on('honkMgr_logBuffer', function(_, buffer) {
    $scope.$apply(function() { $scope.logEntries = buffer; });
    scrollLog();
  });

  $scope.$on('honkMgr_syncStatus', function(_, status) {
    $scope.$apply(function() { $scope.syncSession = status; });
  });

  // ── Init ────────────────────────────────────────────────
  bngApi.engineLua('honkManager.requestFullState()');

}]);