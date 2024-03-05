#!/usr/bin/env ruby
# 

require "json"
require "pp"
require "shellwords"

TF = "tofu"
ORG = "NixOS"

# Just wrap `gh`, it's easier than to depend on Octokit
def gh(*args)
  cmd = ["gh"] + args.map(&:to_s)
  $stderr.puts "# #{cmd.shelljoin}"
  IO.popen(cmd) do |io|
    JSON.load(io, nil, create_additions: false, symbolize_names: true)
  end
end

def name_to_tf(name)
  name.sub(/^[^a-zA-Z]/, "_").gsub(/[^\w-]/, "_").downcase
end

def tf(*args)
  cmd = [TF] + args.map(&:to_s)
  $stderr.puts "# #{cmd.shelljoin}"
  system(*cmd)
end

def tf!(*args)
  if !tf(*args)
    throw "terraform command failed"
  end
end

### Import Organization settings

org_id = gh(:api, "/orgs/#{ORG}", "--jq=.id")

File.open("import_org.tf", "w") do |f|
  f.puts(<<~EOM)
    import {
      id = "#{org_id}"
      to = github_organization_settings.#{ORG}
    }
  EOM
end

### Import REPOS ###


File.open("import_repos.tf", "w") do |f|
  gh(:api, "/orgs/#{ORG}/repos?per_page=100&type=public&sort=full_name", "--paginate").each do |repo|
    name = repo[:name]
    id_name = name_to_tf(name)

    f.puts(<<~EOM)
      import {
        id = "#{name}"
        to = github_repository.#{id_name}
      }

      import {
        id = "#{name}"
        to = github_repository_collaborators.#{id_name}
      }

    EOM
  end
end

### Import teams

File.open("import_teams.tf", "w") do |f|
  gh(:api, "/orgs/#{ORG}/teams?per_page=100", "--paginate").each do |team|
    name = team[:name]
    id = team[:id]
    id_name = name_to_tf(name)

    # has_members = gh(:api, "/orgs/#{ORG}/team/#{id}/members?per_page=1").any?
    # if not has_members then
    #   throw "NO MEMBERS, delete this team: #{name}"
    # end

    f.puts(<<~EOM)
      import {
        id = "#{id}"
        to = github_team.#{id_name}
      }
    
      import {
        id = "#{id}"
        to = github_team_members.#{id_name}
      }
    EOM
  end
end

### Import the resources in the terraform state and generate the terraform resources

File.delete("generated.tf") if File.exists?("generated.tf")

tf!(:plan, "-generate-config-out=generated.tf")
