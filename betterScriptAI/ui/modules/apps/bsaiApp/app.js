'use strict';

angular.module('beamng.apps').directive('bsaiApp', [function() {
  return {
    template: [
      '<div class="bsai-panel">',

      '  <div class="tab-bar">',
      '    <button class="tab-btn" ng-class="{active:activeTab===\'vehicles\'}" ng-click="activeTab=\'vehicles\'">Vehicles</button>',
      '    <button class="tab-btn" ng-class="{active:activeTab===\'sync\'}"     ng-click="activeTab=\'sync\'">Sync / Race</button>',
      '    <button class="tab-btn" ng-class="{active:activeTab===\'debug\'}"    ng-click="activeTab=\'debug\'">Debug Log</button>',
      '  </div>',

      '  <div class="tab-content" ng-show="activeTab===\'vehicles\'">',
      '    <div class="no-vehicles" ng-if="vehicles.length===0">No vehicles spawned</div>',
      '    <div class="vehicle-card" ng-repeat="v in vehicles" ng-class="\'state-\'+v.state">',
      '      <div class="card-header">',
      '        <span class="veh-name">{{ v.name }}</span>',
      '        <span class="state-badge">{{ v.state }}</span>',
      '      </div>',
      '      <div class="card-stats" ng-if="v.state===\'hasData\'||v.state===\'playing\'">',
      '        <span>Honks: <strong>{{ v.honkCount }}</strong></span>',
      '        <span ng-if="v.speedMin!=null">Speed: <strong>{{ v.speedMin|number:1 }} - {{ v.speedMax|number:1 }} mph</strong></span>',
      '      </div>',
      '      <div class="card-stats muted" ng-if="v.state===\'idle\'">No data recorded</div>',
      '      <div class="card-stats recording-pulse" ng-if="v.state===\'recording\'">Recording... {{ v.honkCount }} honk(s)</div>',
      '      <div class="card-actions">',
      '        <button ng-if="v.state===\'idle\'||v.state===\'hasData\'" ng-click="startRecording(v.id)" class="btn btn-record">Record</button>',
      '        <button ng-if="v.state===\'recording\'"                   ng-click="stopRecording(v.id)"  class="btn btn-stop">Stop Rec</button>',
      '        <button ng-if="v.state===\'hasData\'"                     ng-click="playback(v.id)"       class="btn btn-play">Play</button>',
      '        <button ng-if="v.state===\'playing\'"                     ng-click="stopPlayback(v.id)"   class="btn btn-stop">Stop</button>',
      '        <button ng-if="v.state===\'hasData\'||v.state===\'idle\'" ng-click="clearData(v.id)"      class="btn btn-clear">Clear</button>',
      '      </div>',
      '    </div>',
      '  </div>',

      '  <div class="tab-content" ng-show="activeTab===\'sync\'">',
      '    <div class="sync-header">',
      '      <span>Select vehicles to sync:</span>',
      '      <span class="sync-status-badge" ng-class="syncSession.phase">{{ syncSession.phase }}</span>',
      '    </div>',
      '    <div class="no-vehicles" ng-if="vehicles.length===0">No vehicles available</div>',
      '    <div class="sync-vehicle-row" ng-repeat="v in vehicles">',
      '      <label>',
      '        <input type="checkbox"',
      '               ng-disabled="v.state!==\'hasData\'&&v.state!==\'playing\'"',
      '               ng-checked="isSyncParticipant(v.id)"',
      '               ng-click="toggleSyncParticipant(v.id)" />',
      '        <span ng-class="{muted:v.state===\'idle\'||v.state===\'recording\'}">{{ v.name }}</span>',
      '        <span class="state-badge small">{{ v.state }}</span>',
      '      </label>',
      '    </div>',
      '    <div class="sync-footer">',
      '      <span class="muted" ng-if="syncParticipants.length===0">Select 2+ vehicles with recorded data</span>',
      '      <button class="btn btn-sync"',
      '              ng-disabled="syncParticipants.length<2||syncSession.phase===\'playing\'"',
      '              ng-click="triggerSync()">',
      '        Sync Playback ({{ syncParticipants.length }} vehicles)',
      '      </button>',
      '    </div>',
      '  </div>',

      '  <div class="tab-content debug-tab" ng-show="activeTab===\'debug\'">',
      '    <div class="debug-toolbar">',
      '      <select ng-model="logFilter.vehicleId" class="filter-select">',
      '        <option value="">All Vehicles</option>',
      '        <option ng-repeat="v in vehicles" value="{{ v.id }}">{{ v.name }}</option>',
      '      </select>',
      '      <select ng-model="logFilter.type" class="filter-select">',
      '        <option value="">All Types</option>',
      '        <option value="honk">Honk</option>',
      '        <option value="record">Record</option>',
      '        <option value="playback">Playback</option>',
      '        <option value="sync">Sync</option>',
      '        <option value="error">Error</option>',
      '      </select>',
      '      <button class="btn btn-clear small" ng-click="clearLog()">Clear</button>',
      '      <label class="autoscroll-label"><input type="checkbox" ng-model="autoScroll" /> Auto-scroll</label>',
      '    </div>',
      '    <div class="log-viewer" id="logViewer">',
      '      <div class="log-entry type-{{ entry.type }}" ng-repeat="entry in filteredLog()" ng-click="copyLogEntry(entry)">',
      '        <span class="log-time">{{ entry.timestamp }}</span>',
      '        <span class="log-veh" ng-if="entry.vehicleId">[{{ getVehName(entry.vehicleId) }}]</span>',
      '        <span class="log-type">[{{ entry.type }}]</span>',
      '        <span class="log-msg">{{ entry.message }}</span>',
      '      </div>',
      '      <div class="no-vehicles" ng-if="filteredLog().length===0">No log entries</div>',
      '    </div>',
      '  </div>',

      '</div>'
    ].join('\n'),
    replace: true,
    restrict: 'E',
    scope: true,
    controller: ['$scope', '$timeout', function($scope, $timeout) {

      $scope.activeTab        = 'vehicles';
      $scope.vehicles         = [];
      $scope.logEntries       = [];
      $scope.syncParticipants = [];
      $scope.syncSession      = { phase: 'idle', participants: [] };
      $scope.logFilter        = { vehicleId: '', type: '' };
      $scope.autoScroll       = true;

      function findVehicle(id) {
        for (var i = 0; i < $scope.vehicles.length; i++) {
          if ($scope.vehicles[i].id === id) return $scope.vehicles[i];
        }
        return null;
      }

      $scope.getVehName = function(id) {
        var v = findVehicle(id);
        return v ? v.name : ('Vehicle ' + id);
      };

      $scope.isSyncParticipant = function(id) {
        return $scope.syncParticipants.indexOf(id) !== -1;
      };

      $scope.toggleSyncParticipant = function(id) {
        var idx = $scope.syncParticipants.indexOf(id);
        if (idx === -1) $scope.syncParticipants.push(id);
        else            $scope.syncParticipants.splice(idx, 1);
      };

      $scope.filteredLog = function() {
        return $scope.logEntries.filter(function(e) {
          if ($scope.logFilter.vehicleId && String(e.vehicleId) !== $scope.logFilter.vehicleId) return false;
          if ($scope.logFilter.type      && e.type !== $scope.logFilter.type) return false;
          return true;
        });
      };

      function scrollLog() {
        if (!$scope.autoScroll) return;
        $timeout(function() {
          var el = document.getElementById('logViewer');
          if (el) el.scrollTop = el.scrollHeight;
        }, 30);
      }

      $scope.clearLog = function() { $scope.logEntries = []; };

      $scope.copyLogEntry = function(entry) {
        var text = '[' + entry.timestamp + '] [' + entry.type + '] ' + entry.message;
        if (navigator.clipboard) navigator.clipboard.writeText(text);
      };

      $scope.startRecording = function(id) { bngApi.engineLua('extensions.betterScriptAI_core.startRecording(' + id + ')'); };
      $scope.stopRecording  = function(id) { bngApi.engineLua('extensions.betterScriptAI_core.stopRecording('  + id + ')'); };
      $scope.playback       = function(id) { bngApi.engineLua('extensions.betterScriptAI_core.playback('       + id + ')'); };
      $scope.stopPlayback   = function(id) { bngApi.engineLua('extensions.betterScriptAI_core.stopPlayback('   + id + ')'); };
      $scope.clearData      = function(id) { bngApi.engineLua('extensions.betterScriptAI_core.clearData('      + id + ')'); };

      $scope.triggerSync = function() {
        if ($scope.syncParticipants.length < 2) return;
        var json = JSON.stringify($scope.syncParticipants);
        bngApi.engineLua("extensions.betterScriptAI_core.syncPlayback('" + json + "')");
      };

      $scope.$on('bsai_allVehicles', function(_, list) {
        $scope.$apply(function() { $scope.vehicles = list; });
      });

      $scope.$on('bsai_vehicleUpdate', function(_, v) {
        $scope.$apply(function() {
          var idx = -1;
          for (var i = 0; i < $scope.vehicles.length; i++) {
            if ($scope.vehicles[i].id === v.id) { idx = i; break; }
          }
          if (idx === -1) $scope.vehicles.push(v);
          else            $scope.vehicles[idx] = v;
        });
      });

      $scope.$on('bsai_logEntry', function(_, entry) {
        $scope.$apply(function() {
          $scope.logEntries.push(entry);
          if ($scope.logEntries.length > 500) $scope.logEntries.shift();
        });
        scrollLog();
      });

      $scope.$on('bsai_logBuffer', function(_, buffer) {
        $scope.$apply(function() { $scope.logEntries = buffer; });
        scrollLog();
      });

      $scope.$on('bsai_syncStatus', function(_, status) {
        $scope.$apply(function() { $scope.syncSession = status; });
      });

      bngApi.engineLua('extensions.betterScriptAI_core.requestFullState()');
    }]
  };
}]);