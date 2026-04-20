#!/usr/bin/env node

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

function usage() {
  process.stdout.write(`Usage:
  node ./scripts/install-config-helper.mjs claude-mcp <config-path> <project-root> <server-name> <command-name>
  node ./scripts/install-config-helper.mjs codex-mcp <config-path> <server-name> <command-name>
  node ./scripts/install-config-helper.mjs codex-plugin-version <plugin-manifest-path>
  node ./scripts/install-config-helper.mjs codex-plugin-config <config-path> <repo-root> <marketplace-name> <plugin-name>
`);
}

function readTextIfExists(filePath) {
  if (!existsSync(filePath)) {
    return "";
  }
  return readFileSync(filePath, "utf8");
}

function ensureParentDir(filePath) {
  mkdirSync(path.dirname(filePath), { recursive: true });
}

function normalizeNewlines(text) {
  return text.replace(/\r\n/g, "\n");
}

function trimTrailingBlankLines(lines) {
  let end = lines.length;
  while (end > 0 && lines[end - 1].trim() === "") {
    end -= 1;
  }
  return lines.slice(0, end);
}

function canonicalSectionBody(bodyLines) {
  const lines = [...bodyLines];
  while (lines.length > 0 && lines[0].trim() === "") {
    lines.shift();
  }
  while (lines.length > 0 && lines[lines.length - 1].trim() === "") {
    lines.pop();
  }
  return lines.join("\n");
}

function splitTomlSections(text) {
  const normalized = normalizeNewlines(text);
  if (normalized.length === 0) {
    return { preambleLines: [], sections: [] };
  }

  const lines = normalized.split("\n");
  const preambleLines = [];
  const sections = [];
  let currentHeader = null;
  let currentBodyLines = [];

  for (const line of lines) {
    const headerMatch = line.match(/^\[([^\]]+)\]\s*$/);
    if (headerMatch) {
      if (currentHeader === null) {
        preambleLines.push(...currentBodyLines);
      } else {
        sections.push({ header: currentHeader, bodyLines: currentBodyLines });
      }
      currentHeader = headerMatch[1];
      currentBodyLines = [];
      continue;
    }
    currentBodyLines.push(line);
  }

  if (currentHeader === null) {
    preambleLines.push(...currentBodyLines);
  } else {
    sections.push({ header: currentHeader, bodyLines: currentBodyLines });
  }

  return { preambleLines, sections };
}

function renderTomlDocument(document) {
  const chunks = [];
  const preamble = trimTrailingBlankLines(document.preambleLines);
  if (preamble.length > 0) {
    chunks.push(preamble.join("\n"));
  }

  for (const section of document.sections) {
    const bodyLines = trimTrailingBlankLines(section.bodyLines);
    if (bodyLines.length > 0) {
      chunks.push(`[${section.header}]\n${bodyLines.join("\n")}`);
    } else {
      chunks.push(`[${section.header}]`);
    }
  }

  return chunks.length > 0 ? `${chunks.join("\n\n")}\n` : "";
}

function ensureUniqueManagedHeaders(document, headers, configPath) {
  for (const header of headers) {
    const count = document.sections.filter((section) => section.header === header).length;
    if (count > 1) {
      fail(`Existing Codex config has duplicate section [${header}] in ${configPath}; refusing to modify it.`);
    }
  }
}

function applyTomlSectionUpdates(text, updates, configPath) {
  const document = splitTomlSections(text);
  const managedHeaders = [
    ...updates.removeHeaders,
    ...updates.upserts.map((entry) => entry.header),
  ];
  ensureUniqueManagedHeaders(document, managedHeaders, configPath);

  const upsertMap = new Map(
    updates.upserts.map((entry) => [
      entry.header,
      {
        header: entry.header,
        bodyLines: normalizeNewlines(entry.body).split("\n"),
      },
    ]),
  );
  const removeSet = new Set(updates.removeHeaders);
  const nextSections = [];
  const insertedHeaders = new Set();

  for (const section of document.sections) {
    if (removeSet.has(section.header)) {
      continue;
    }
    if (upsertMap.has(section.header)) {
      nextSections.push(upsertMap.get(section.header));
      insertedHeaders.add(section.header);
      continue;
    }
    nextSections.push(section);
  }

  for (const entry of updates.upserts) {
    if (!insertedHeaders.has(entry.header)) {
      nextSections.push(upsertMap.get(entry.header));
    }
  }

  return renderTomlDocument({
    preambleLines: document.preambleLines,
    sections: nextSections,
  });
}

function installClaudeMcp(configPath, projectRoot, serverName, commandName) {
  const desiredEntry = {
    type: "stdio",
    command: commandName,
    args: ["mcp"],
  };
  const legacyServerName = "open-codex-computer-use";

  const raw = readTextIfExists(configPath);
  let data;

  if (raw.trim().length === 0) {
    data = {};
  } else {
    try {
      data = JSON.parse(raw);
    } catch (error) {
      fail(`Existing Claude config is not valid JSON: ${error.message}`);
    }
  }

  if (data === null || Array.isArray(data) || typeof data !== "object") {
    fail("Existing Claude config root is not a JSON object; refusing to modify it.");
  }

  const projects = data.projects ?? {};
  if (projects === null || Array.isArray(projects) || typeof projects !== "object") {
    fail('Existing Claude config has non-object "projects"; refusing to modify it.');
  }
  data.projects = projects;

  const projectEntry = projects[projectRoot] ?? {};
  if (projectEntry === null || Array.isArray(projectEntry) || typeof projectEntry !== "object") {
    fail(`Existing Claude project entry for ${projectRoot} is not an object; refusing to modify it.`);
  }
  projects[projectRoot] = projectEntry;

  const mcpServers = projectEntry.mcpServers ?? {};
  if (mcpServers === null || Array.isArray(mcpServers) || typeof mcpServers !== "object") {
    fail(`Existing Claude project MCP config for ${projectRoot} is not an object; refusing to modify it.`);
  }
  projectEntry.mcpServers = mcpServers;

  const target = mcpServers[serverName];
  const legacy = mcpServers[legacyServerName];
  const targetMatches = JSON.stringify(target) === JSON.stringify(desiredEntry);
  const legacyMatches = JSON.stringify(legacy) === JSON.stringify(desiredEntry);

  if (targetMatches && !legacyMatches) {
    process.stdout.write(`Claude MCP server "${serverName}" is already installed for ${projectRoot} in ${configPath}.\n`);
    return;
  }

  mcpServers[serverName] = desiredEntry;
  if (legacyMatches) {
    delete mcpServers[legacyServerName];
  }

  ensureParentDir(configPath);
  writeFileSync(configPath, `${JSON.stringify(data, null, 2)}\n`, "utf8");

  if (targetMatches && legacyMatches) {
    process.stdout.write(`Claude MCP server "${serverName}" was already installed for ${projectRoot}; removed legacy alias "${legacyServerName}" from ${configPath}.\n`);
  } else {
    process.stdout.write(`Installed Claude MCP server "${serverName}" for ${projectRoot} into ${configPath}.\n`);
  }
}

function installCodexMcp(configPath, serverName, commandName) {
  const desiredBody = `command = ${JSON.stringify(commandName)}\nargs = ["mcp"]`;
  const targetHeader = `mcp_servers."${serverName}"`;
  const legacyServerName = "open-codex-computer-use";
  const legacyHeader = `mcp_servers."${legacyServerName}"`;
  const text = readTextIfExists(configPath);
  const document = splitTomlSections(text);

  ensureUniqueManagedHeaders(document, [targetHeader, legacyHeader], configPath);

  const targetSection = document.sections.find((section) => section.header === targetHeader);
  const legacySection = document.sections.find((section) => section.header === legacyHeader);
  const desiredCanonical = canonicalSectionBody(desiredBody.split("\n"));
  const targetMatches = targetSection ? canonicalSectionBody(targetSection.bodyLines) === desiredCanonical : false;
  const legacyMatches = legacySection ? canonicalSectionBody(legacySection.bodyLines) === desiredCanonical : false;

  if (targetMatches && !legacyMatches) {
    process.stdout.write(`Codex MCP server "${serverName}" is already installed in ${configPath}.\n`);
    return;
  }

  const nextText = applyTomlSectionUpdates(
    text,
    {
      removeHeaders: [legacyHeader],
      upserts: [{ header: targetHeader, body: desiredBody }],
    },
    configPath,
  );

  ensureParentDir(configPath);
  writeFileSync(configPath, nextText, "utf8");

  if (targetMatches && legacyMatches) {
    process.stdout.write(`Codex MCP server "${serverName}" was already installed; removed legacy alias "${legacyServerName}" from ${configPath}.\n`);
  } else {
    process.stdout.write(`Installed Codex MCP server "${serverName}" into ${configPath}.\n`);
  }
}

function printCodexPluginVersion(pluginManifestPath) {
  let manifest;
  try {
    manifest = JSON.parse(readFileSync(pluginManifestPath, "utf8"));
  } catch (error) {
    fail(`Failed to read plugin manifest ${pluginManifestPath}: ${error.message}`);
  }

  if (!manifest || typeof manifest.version !== "string" || manifest.version.length === 0) {
    fail(`Plugin manifest ${pluginManifestPath} does not contain a valid string "version".`);
  }

  process.stdout.write(`${manifest.version}\n`);
}

function installCodexPluginConfig(configPath, repoRoot, marketplaceName, pluginName) {
  const text = readTextIfExists(configPath);
  const repoRootPath = path.resolve(repoRoot);
  const nextText = applyTomlSectionUpdates(
    text,
    {
      removeHeaders: [
        'mcp_servers."open-codex-computer-use"',
        'mcp_servers."open-computer-use"',
      ],
      upserts: [
        {
          header: `marketplaces.${marketplaceName}`,
          body: `source_type = "local"\nsource = ${JSON.stringify(repoRootPath)}`,
        },
        {
          header: `plugins."${pluginName}@${marketplaceName}"`,
          body: "enabled = true",
        },
      ],
    },
    configPath,
  );

  ensureParentDir(configPath);
  writeFileSync(configPath, nextText, "utf8");
}

function main(argv) {
  const [command, ...args] = argv;
  switch (command) {
    case "claude-mcp":
      if (args.length !== 4) {
        usage();
        process.exit(1);
      }
      installClaudeMcp(...args);
      return;
    case "codex-mcp":
      if (args.length !== 3) {
        usage();
        process.exit(1);
      }
      installCodexMcp(...args);
      return;
    case "codex-plugin-version":
      if (args.length !== 1) {
        usage();
        process.exit(1);
      }
      printCodexPluginVersion(args[0]);
      return;
    case "codex-plugin-config":
      if (args.length !== 4) {
        usage();
        process.exit(1);
      }
      installCodexPluginConfig(...args);
      return;
    default:
      usage();
      process.exit(1);
  }
}

main(process.argv.slice(2));
