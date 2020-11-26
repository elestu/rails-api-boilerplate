require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_creator"
require "dependabot/omnibus"
#require "gitlab"
#require "./monkey_patch.rb"

github_token = "4368cd79b7e74bd4c978c2b2d7f3814093c38fc2"
package_manager = ENV["PACKAGE_MANAGER"] || "bundler"
repo_name = ENV["REPO_PATH"] || "elestu/rails-api-boilerplate" # namespace/project - Full name of the repo you want to create pull requests for.
directory = ENV["DEP_PATH"] || "/" # Directory where the base dependency files are.
branch = "master"
blacklist = ENV["BLACKLIST"] || nil

# Name of the package manager you'd like to do the update for. Options are:
# - bundler
# - pip (includes pipenv)
# - npm_and_yarn
# - maven
# - gradle
# - cargo
# - hex
# - composer
# - nuget
# - dep
# - go_modules
# - elm
# - submodules
# - docker
# - terraform

credentials = [
  	{
		"type" => "git_source",
		"host" => "github.com",
		"username" => "x-access-token",
		"password" => github_token # A GitHub access token with read access to public repos
  	}
]
source = Dependabot::Source.new(
  provider: "github",
  repo: repo_name,
  directory: directory,
  branch: branch
)
##############################
# Fetch the dependency files #
##############################
puts "Fetching #{package_manager} dependency files for #{repo_name}"
fetcher = Dependabot::FileFetchers.for_package_manager(package_manager).new(
  	source: source,
  	credentials: credentials,
)

files = fetcher.files
commit = fetcher.commit

##############################
# Parse the dependency files #
##############################
puts "Parsing dependencies information"
parser = Dependabot::FileParsers.for_package_manager(package_manager).new(
  	dependency_files: files,
  	source: source,
  	credentials: credentials,
)


begin
    dependencies = parser.parse
rescue Dependabot::DependencyFileNotParseable => e
    puts e.file_path
    puts e.cause.message
end

dependencies.select(&:top_level?).each do |dep|

		#########################################
		# Get update details for the dependency #
		#########################################
		checker = Dependabot::UpdateCheckers.for_package_manager(package_manager).new(
			dependency: dep,
			dependency_files: files,
			credentials: credentials,
			)

		next if checker.up_to_date?

		requirements_to_unlock =
			if !checker.requirements_unlocked_or_can_be?
				if checker.can_update?(requirements_to_unlock: :none) then :none
				else :update_not_possible
				end
			elsif checker.can_update?(requirements_to_unlock: :own) then :own
			elsif checker.can_update?(requirements_to_unlock: :all) then :all
			else :update_not_possible
			end

		next if requirements_to_unlock == :update_not_possible

		updated_deps = checker.updated_dependencies(
			requirements_to_unlock: requirements_to_unlock
		)

		#####################################
		# Generate updated dependency files #
		#####################################
		#
		print "  - Updating #{dep.name}…"
		updater = Dependabot::FileUpdaters.for_package_manager(package_manager).new(
			dependencies: updated_deps,
			dependency_files: files,
			credentials: credentials,
			)

		updated_files = updater.updated_dependency_files
		########################################
		# Create a pull request for the update #
		########################################
    	pr_creator = Dependabot::PullRequestCreator.new(
			source: source,
			base_commit: commit,
			dependencies: updated_deps,
			files: updated_files,
			credentials: credentials,
			label_language: true,
    	)
    	pull_request = pr_creator.create
    	puts " done"
end

puts "Done"
