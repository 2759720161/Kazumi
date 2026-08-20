import { hapTasks, OhosHapContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { getNode } from '@ohos/hvigor';
import * as fs from 'fs';
import * as path from 'path';

interface AppBuildInfo {
  appName: string;
  versionName: string;
  versionCode: string;
}

function toArtifactName(value: string): string {
  return value.replace(/[^\da-zA-Z._-]/g, '_');
}

function readAppBuildInfo(): AppBuildInfo {
  const projectRoot = path.resolve(__dirname, '..');
  const appJsonPath = path.join(projectRoot, 'AppScope', 'app.json5');
  const appJsonText = fs.readFileSync(appJsonPath, 'utf8');
  const versionNameMatch = appJsonText.match(/"versionName"\s*:\s*"([^"]+)"/);
  const versionCodeMatch = appJsonText.match(/"versionCode"\s*:\s*(\d+)/);
  const labelMatch = appJsonText.match(/"label"\s*:\s*"\$string:([^"]+)"/);
  const stringName = labelMatch ? labelMatch[1] : 'app_name';
  const stringJsonPath = path.join(
    projectRoot,
    'AppScope',
    'resources',
    'base',
    'element',
    'string.json'
  );

  let appName = 'FanPlayer';
  if (fs.existsSync(stringJsonPath)) {
    const stringJson = JSON.parse(fs.readFileSync(stringJsonPath, 'utf8')) as {
      string?: Array<{ name: string; value: string }>;
    };
    const appNameEntry = (stringJson.string ?? []).find((item) => item.name === stringName);
    if (appNameEntry && appNameEntry.value.trim().length > 0) {
      appName = appNameEntry.value.trim();
    }
  }

  return {
    appName,
    versionName: versionNameMatch ? versionNameMatch[1] : '1.0.0',
    versionCode: versionCodeMatch ? versionCodeMatch[1] : '1'
  };
}

const entryNode = getNode(__filename);
if (entryNode) {
  entryNode.afterNodeEvaluate((node) => {
    const hapContext = node.getContext(OhosPluginId.OHOS_HAP_PLUGIN) as OhosHapContext;
    if (!hapContext) {
      return;
    }

    const buildInfo = readAppBuildInfo();
    const artifactName = toArtifactName(
      `${buildInfo.appName}${buildInfo.versionName}_${buildInfo.versionCode}`
    );
    const buildProfile = hapContext.getBuildProfileOpt();
    for (const target of buildProfile.targets ?? []) {
      if (target.name === 'default') {
        target.output = {
          ...(target.output ?? {}),
          artifactName
        };
      }
    }
    hapContext.setBuildProfileOpt(buildProfile);
  });
}

export default {
  system: hapTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: []       /* Custom plugin to extend the functionality of Hvigor. */
}
