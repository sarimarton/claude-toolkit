import React from 'react';
import { Box, Text } from 'ink';
import { StatusTable } from './StatusTable.js';
import { InstallProgress } from './InstallProgress.js';
import { DoctorReport } from './DoctorReport.js';
import { ModuleTree } from './ModuleTree.js';
import { UsageChart } from './UsageChart.js';

interface AppProps {
  command: string;
  args: string[];
  flags: { yes: boolean };
}

export function App({ command, args, flags }: AppProps) {
  switch (command) {
    case 'list':
    case 'status':
      return <StatusTable detailed={command === 'status'} />;

    case 'install':
      return <InstallProgress modules={args} autoConfirm={flags.yes} />;

    case 'uninstall':
      return <InstallProgress modules={args} autoConfirm={flags.yes} uninstall />;

    case 'doctor':
      return <DoctorReport />;

    case 'upgrade':
      return <InstallProgress modules={[]} autoConfirm={flags.yes} upgrade />;

    case 'chart':
      return <UsageChart />;

    case 'dashboard':
      return <ModuleTree />;

    default:
      return (
        <Box flexDirection="column">
          <Text color="red">Unknown command: {command}</Text>
          <Text dimColor>Run claude-toolkit --help for usage</Text>
        </Box>
      );
  }
}
